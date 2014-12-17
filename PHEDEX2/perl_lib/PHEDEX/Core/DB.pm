package PHEDEX::Core::DB;

use strict;
use warnings;
use base 'Exporter', 'PHEDEX::Core::Logging';
our @EXPORT = qw(parseDatabaseInfo connectToDatabase disconnectFromDatabase connectionValid
		 dbsql dbexec dbprep dbbindexec);
use PHEDEX::Core::Timing;
use PHEDEX::Core::Net;
use DBI;
use Cwd;

# Errors for which the database handle is invalid and a reconnection
# should occur
our @ORA_INVALID_ERRORS = ( '03113',  # End-of-file on communication channel
			    '03114',  # not connected to Oracle
			    '03135',  # Connection lost contact
			    '01031',  # insufficient privileges
			    '01012',  # not logged on
			    '01003',  # no statement parsed
			    '12545',  # target host or object does not exist
			    '17008',  # closed connection
			    '25408',  # can not safely replay call
			    );
my $joined = join "|", @ORA_INVALID_ERRORS;
our $ORA_INVALID_REGEX = qr/ORA-(?:$joined):/;

# Errors for which the problem was serious and we should just die
our @ORA_EXIT_ERRORS = ( '01017',  # Invalid username or password
			 '28001'   # The password has expired 
			 );
$joined = join "|", @ORA_EXIT_ERRORS;
our $ORA_EXIT_REGEX = qr/ORA-(?:$joined):/;

# Parse database connection arguments.
sub parseDatabaseInfo
{
    my ($self) = @_;

    $self->{DBH_LIFE} = 86400;
    if ($self->{DBCONFIG} =~ /(.*):(.*)/)
    {
	$self->{DBCONFIG} = $1;
	$self->{DBSECTION} = $2;
    }

    my $insection = $self->{DBSECTION} ? 0 : 1;
    open (DBCONF, "< $self->{DBCONFIG}")
	or die "$self->{DBCONFIG}: $!\n";

    while (<DBCONF>)
    {
	chomp; s/#.*//; s/^\s+//; s/\s+$//; s/\s+/ /g; next if /^$/;
	if (/^Section (\S+)$/) {
	    $insection = ($1 eq $self->{DBSECTION});
	} elsif (/^Interface (\S+)$/) {
	    $self->{DBH_DBITYPE} = $1 if $insection;
	} elsif (/^Database (\S+)$/) {
	    $self->{DBH_DBNAME} = $1 if $insection;
	} elsif (/^AuthDBUsername (\S+)$/) {
	    $self->{DBH_DBUSER} = $1 if $insection;
	} elsif (/^AuthDBPassword (\S+)$/) {
	    $self->{DBH_DBPASS} = $1 if $insection;
	} elsif (/^AuthRole (\S+)$/) {
	    $self->{DBH_DBROLE} = $1 if $insection;
	} elsif (/^AuthRolePassword (\S+)$/) {
	    $self->{DBH_DBROLE_PASS} = $1 if $insection;
	} elsif (/^ConnectionLife (\d+)$/) {
	    $self->{DBH_LIFE} = $1 if $insection;
	    $self->{DBH_CACHE} = 0 if $insection && $1 == 0;
	} elsif (/^LogConnection (on|off)$/) {
	    $self->{DBH_LOGGING} = ($1 eq 'on') if $insection;
	} elsif (/^LogSQL (on|off)$/) {
	    $ENV{PHEDEX_LOG_SQL} = ($1 eq 'on') if $insection && !exists $ENV{PHEDEX_LOG_SQL};
	} elsif (/^SimDBFail (\S+)$/) {
	    $ENV{PHEDEX_SIM_DB_FAIL} = $1 if $insection && !exists $ENV{PHEDEX_SIM_DB_FAIL};
	} elsif (/^SessionSQL (.*)$/) {
	    push(@{$self->{DBH_SESSION_SQL}}, $1);
	} elsif (/^SchemaPrefix (.*)$/) {
	    push(@{$self->{DBH_SCHEMA_PREFIX}}, $1);
	} else {
	    die "$self->{DBCONFIG}: $.: Unrecognised line\n";
	}
    }
    close (DBCONF);

    die "$self->{DBCONFIG}: database parameters not found\n"
	if (! $self->{DBH_DBITYPE} || ! $self->{DBH_DBNAME}
	    || ! $self->{DBH_DBUSER} || ! $self->{DBH_DBPASS});

    die "$self->{DBCONFIG}: role specified without username or password\n"
	if ($self->{DBH_DBROLE} && ! $self->{DBH_DBROLE_PASS});
}



# Create a connection to the transfer database and cache it.  Parses
# the file $self->{DBCONFIG} if it is available. Otherwise the
# parameters: DBITYPE, DBNAME, DBUSER, DBPASS must be set. Database
# connections are cached into $self->{DBH}.
sub connectToDatabase
{
  my ($self) = @_;

  # If we have database configuration file, read it
  &parseDatabaseInfo ($self) if ($self->{DBCONFIG} && ! $self->{DBH_DBNAME});

  # Use cached connection if it's still alive and the handle
  # isn't too old, otherwise create new one.
  my $dbh = $self->{DBH};
  if (! &connectionValid( $dbh ) )
  {
    $self->{DBH_LOGGING} = 1 if $ENV{PHEDEX_LOG_DB_CONNECTIONS};
    &PHEDEX::Core::Logging::Logmsg ($self, "(re)connecting to database") if $self->{DBH_LOGGING};

    # Clear previous connection.
    eval { &disconnectFromDatabase ($self, $self->{DBH}, 1) } if $self->{DBH};
    undef $self->{DBH};

    # Start a new connection.
    $self->{DBH_ID_HOST} = &getfullhostname();
    $self->{DBH_ID_MODULE} = $0; $self->{DBH_ID_MODULE} =~ s!.*/!!;

    $self->{DBH_ID_LABEL} = $self->{LOGFILE} || ""; $self->{DBH_ID_LABEL} =~ s!.*/!!;
    $self->{DBH_ID_LABEL} = " ($self->{DBH_ID_LABEL})" if $self->{DBH_ID_LABEL};
    $self->{DBH_ID} = "$self->{DBH_ID_MODULE}\@$self->{DBH_ID_HOST}$self->{DBH_ID_LABEL}";
    if ( $self->{SHARED_DBH} )
    {
      &PHEDEX::Core::Logging::Logmsg($self, "Looking for a DBH to share") if $self->{DEBUG};
      if ( exists($Agent::Registry{DBH}) && &connectionValid($Agent::Registry{DBH}))
      {
        $self->{DBH} = $dbh = $Agent::Registry{DBH};
        &PHEDEX::Core::Logging::Logmsg($self, "using shared DBH=$dbh") if $self->{DEBUG};
      }
      else
      {
        &PHEDEX::Core::Logging::Logmsg($self,"Creating new shared DBH") if $self->{DEBUG};
        $self->{DBH} = $dbh = $Agent::Registry{DBH} =
            DBI->connect ("DBI:$self->{DBH_DBITYPE}:$self->{DBH_DBNAME}",
	    		 $self->{DBH_DBUSER}, $self->{DBH_DBPASS},
			 { RaiseError => 1,
			   AutoCommit => 0,
			   PrintError => 0,
			   ora_module_name => $self->{DBH_ID} });
      }
    }
    else
    {
        &PHEDEX::Core::Logging::Logmsg ($self, "Creating new private DBH") if $self->{DEBUG};
        $self->{DBH} = $dbh =
            DBI->connect ("DBI:$self->{DBH_DBITYPE}:$self->{DBH_DBNAME}",
	    		 $self->{DBH_DBUSER}, $self->{DBH_DBPASS},
			 { RaiseError => 1,
			   AutoCommit => 0,
			   PrintError => 0,
			   ora_module_name => $self->{DBH_ID} });
    }

    die "failed to connect to the database\n" if ! $dbh;

    # Acquire role if one was specified.  Do not use &dbexec() here
    # as it will expose the password used in the logs.
    if ($self->{DBH_DBROLE})
    {
      eval { $dbh->do ("set role $self->{DBH_DBROLE} identified by"
		             . " \"$self->{DBH_DBROLE_PASS}\"") };
      die "failed to authenticate to $self->{DBH_DBNAME} as"
        . " $self->{DBH_DBUSER} using role $self->{DBH_DBROLE}\n"
	if $@;
    }

    # Execute session SQL statements.
    &dbexec($dbh, $_) for @{$self->{DBH_SESSION_SQL}};

    # Cache it.
    $dbh->{FetchHashKeyName} = "NAME_uc";
    $dbh->{LongReadLen} = 4096;
    $dbh->{RowCacheSize} = 1000;
    $dbh->{private_phedex_invalid} = 0;
    $dbh->{private_phedex_prefix} = $self->{DBH_SCHEMA_PREFIX};
    $dbh->{private_phedex_newconn} = 1;
    $dbh->{private_phedex_age} = time();
    $dbh->{private_phedex_life} = $self->{DBH_LIFE};
    $self->{DBH} = $dbh;
  }

  # Reset statement cache
  $dbh->{private_phedex_stmtcache} = {};

  return $dbh;
}

# Disconnect from the database.  Normally this does nothing, as we
# cache the connection and try to keep it alive as long as we can
# without disturbing program robustness.  If $self->{DBH_CACHE} is
# defined and zero, connection caching is turned off.
sub disconnectFromDatabase
{
  my ($self, $dbh, $force) = @_;

  # Finish statements in the cache.
  $_->finish() for values %{$dbh->{private_phedex_stmtcache}};
  $dbh->{private_phedex_stmtcache} = {};

  # Actually disconnect if required.
  if ((exists $self->{DBH_CACHE} && ! $self->{DBH_CACHE}) || $force)
  {
    &PHEDEX::Core::Logging::Logmsg ($self, "disconnected from database") if $self->{DBH_LOGGING};
    eval { $dbh->disconnect() } if $dbh;
    undef $dbh;
    undef $self->{DBH};
  }
}

# Check whether the connection is valid by a variety of methods
sub connectionValid
{
    my ($self) = @_;
    return 0 if !$self;
    my $dbh = $self->isa('DBI::db') ? $self : $self->{DBH}; # dbh is either the arg or the DBH of the arg

                                                                         # Bad things:
    if (! $dbh                                                           #   no database handle
	|| $dbh->{private_phedex_invalid}                                #   handle marked invalid elsewhere
	|| time() - $dbh->{private_phedex_age} > $dbh->{private_phedex_life} #   connection too old
	|| (! eval { $dbh->ping() } || $@)                               #   DBI ping fails
	|| (! eval { $dbh->do("select sysdate from dual") } || $@)) {    #   basic query fails
	return 0;
    }

    return 1;
}


######################################################################
# Tidy up SQL statement
sub dbsql
{
  my ($sql) = @_;
  $sql =~ s/--.*//mg;
  $sql =~ s/^\s+//mg;
  $sql =~ s/\s+$//mg;
  $sql =~ s/\n/ /g;
  return $sql;
}

# Simple utility to prepare a SQL statement
sub dbprep
{
  my ($dbh, $sql) = @_;
  if (my $stmt = $dbh->{private_phedex_stmtcache}{$sql})
  {
    $stmt->finish();
    return $stmt;
  }

  my $stmt = eval { return ($dbh->{private_phedex_stmtcache}{$sql}
			      = $dbh->prepare (&dbsql ($sql))) };
  return $stmt if ! $@;

  # Handle disconnected oracle handle, flag the handle bad
  $dbh->{private_phedex_invalid} = 1
      if ($@ =~ /$ORA_INVALID_REGEX/ || $@ =~ /TNS:listener/);

  &PHEDEX::Core::Logging::Fatal(undef, $@) if $@ =~ /$ORA_EXIT_REGEX/;
  die $@," (for $sql)";
}

# Simple utility to prepare, bind and execute a SQL statement.  In
# list context returns the statement handle executed, the return value
# of the execution, and the duration the execution took.  In scalar
# context returns only the statement handle.
sub dbexec
{
  my ($dbh, $sql, %params) = @_;
  my $stmt = &dbprep ($dbh, $sql);
  my ($rv, $dt) = &dbbindexec ($stmt, %params);
  return wantarray ? ($stmt, $rv, $dt) : $stmt;
}

# Simple bind and execute a SQL statement.  In list context returns
# the return value of the execution and the duration the execution took.
# In scalar context returns only return value of the execution.
sub dbbindexec
{
  my ($stmt, %params) = @_;
  my $t1 = &mytimeofday();

  if ($ENV{PHEDEX_LOG_SQL})
  {
    my $sql = $stmt->{Statement};
    $sql =~ s/\s+/ /g; $sql =~ s/^\s+//; $sql =~ s/\s+$//;
    my $bound = join (", ", map { "($_, " . (defined $params{$_} ? $params{$_} : "undef") . ")" } sort keys %params);
    print PHEDEX::Core::Logging::Hdr,"executing statement `$sql' [$bound]";
  }

  my $isarray = 0;
  while (my ($param, $val) = each %params)
  {
    if (ref $val eq 'ARRAY')
    {
     $stmt->bind_param_array ($param, $val);
     $isarray++;
    }
    elsif (ref $val)
    {
     $stmt->bind_param_inout ($param, $val, 4096);
    }
    else
    {
      $stmt->bind_param ($param, $val);
    }
  }

  my $rv = eval {
    # Used to simulate an oracle failure
    if ($ENV{PHEDEX_SIM_DB_FAIL} &&
	$ENV{PHEDEX_SIM_DB_FAIL} < rand()) {
	die "ORA-XXXXX: simulating oracle failure with probability P=",sprintf("%.2f",$ENV{PHEDEX_SIM_DB_FAIL});
    }
    
    return $isarray
	    ? $stmt->execute_array({ ArrayTupleStatus => [] })
	    : $stmt->execute();
  };
  my $dt = &mytimeofday() - $t1;

  if ($ENV{PHEDEX_LOG_SQL})
  {
      print " dt=",sprintf("%0.5f",$dt),"\n";
  }

  if (! $@ ) {
      return wantarray ? ($rv, $dt) : $rv;
  }

  print "\n" if ($ENV{PHEDEX_LOG_SQL}); # finish log line if exectue failed

  # Flag handle bad on disconnected oracle handle
  $stmt->{Database}{private_phedex_invalid} = 1
      if ($@ =~ /$ORA_INVALID_REGEX/ || $@ =~ /TNS:listener/);

  &PHEDEX::Core::Logging::Fatal(undef, $@) if $@ =~ /$ORA_EXIT_REGEX/;
  die $@;
}

1;
