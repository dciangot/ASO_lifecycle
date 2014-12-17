package PHEDEX::Transfer::Backend::Monitor;

use strict;
use warnings;
use base 'PHEDEX::Core::Logging';
use POE::Session;
use POE::Queue::Array;
use PHEDEX::Monalisa;

our %params =
	(
	  Q_INTERFACE		=> undef, # A transfer queue interface object
	  Q_INTERVAL		=> 60,	  # Queue polling interval
	  Q_TIMEOUT		=> 60,	  # Timeout for Q_INTERFACE commands
	  J_INTERVAL		=>  5,	  # Job polling interval
	  POLL_QUEUE		=>  0,	  # Poll the queue or not?
	  ME			=> 'QMon',# Arbitrary name for this object
	  STATISTICS_INTERVAL	=> 60,	  # Interval for reporting statistics
	  JOB_POSTBACK		=> undef, # Callback for job state changes
	  FILE_POSTBACK		=> undef, # Callback for file state changes
	  SANITY_INTERVAL	=> 60,	  # Interval for internal sanity-checks
	  DEBUG			=> $ENV{PHEDEX_DEBUG} || 0,
 	  VERBOSE		=> $ENV{PHEDEX_VERBOSE} || 0,
	);
our %ro_params =
	(
	  QUEUE	=> undef,	# A POE::Queue of transfer jobs...
	  WORKSTATS	=> {},	# Statistics on the job or file states
	  LINKSTATS     => {},  # Statistics on the link TODO:  combine with WORKSTATS
	  JOBS		=> {},  # A hash of Job-IDs.
	  APMON => undef,	# A PHEDEX::Monalisa object, if I want it!
	  LAST_SUCCESSFULL_POLL => time,	# When I last got a job status
	);
our $dbg=1;

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = ref($proto) ? $class->SUPER::new(@_) : {};

  my %args = (@_);
  map {
        $self->{$_} = defined($args{$_}) ? delete $args{$_} : $params{$_}
      } keys %params;
  map {
        $self->{$_} = defined($args{$_}) ? delete $args{$_} : $ro_params{$_}
      } keys %ro_params;

  $self->{QUEUE} = POE::Queue::Array->new();
  bless $self, $class;

  POE::Session->create
	(
	  object_states =>
	  [
	    $self =>
	    {
	      poll_queue		=> 'poll_queue',
	      poll_queue_postback	=> 'poll_queue_postback',
	      poll_job			=> 'poll_job',
	      poll_job_postback		=> 'poll_job_postback',
	      report_job		=> 'report_job',
	      report_statistics		=> 'report_statistics',
	      forget_job    		=> 'forget_job',
	      shoot_myself		=> 'shoot_myself',

	      _default	 => '_default',
	      _stop	 => '_stop',
	      _start	 => '_start',
	      _child	 => '_child',
            },
          ],
	);

# Sanity checks:
  $self->{J_INTERVAL}>0 or die "J_INTERVAL too small:",$self->{J_INTERVAL},"\n";
  $self->{Q_INTERVAL}>0 or die "Q_INTERVAL too small:",$self->{Q_INTERVAL},"\n";
  ref($self->{Q_INTERFACE}) or die "No sensible Q_INTERFACE object defined.\n";

# foreach ( qw / ListQueue ListJob / )
# { $self->{Q_INTERFACE}->can($_) or warn "Q_INTERFACE cannot \"$_\"?\n"; }
  foreach ( qw / StatePriority / )
  { $self->{Q_INTERFACE}->can($_) or die "Q_INTERFACE cannot \"$_\"?\n"; }

  return $self;
}

sub AUTOLOAD
{
  my $self = shift;
  my $attr = our $AUTOLOAD;
  $attr =~ s/.*:://;

  return $self->{$attr} if exists $ro_params{$attr};

  if ( exists($params{$attr}) )
  {
    $self->{$attr} = shift if @_;
    return $self->{$attr};
  }

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  my $parent = "SUPER::" . $attr;
  $self->$parent(@_);
}

sub _stop
{
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
  $self->Logmsg("is ending, for lack of work...");
}

sub _default
{
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
  my $ref = ref($self);
  die <<EOF;

  Default handler for class $ref:
  The default handler caught an unhandled "$_[ARG0]" event.
  The $_[ARG0] event was given these parameters: @{$_[ARG1]}

  (...end of dump)
EOF
}

sub _start
{
  my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];
  $self->Logmsg("is starting (session ",$session->ID,")");

  $self->{SESSION_ID} = $session->ID;
  $kernel->alias_set($self->{ME});

  my $poll_queue_postback  = $session->postback( 'poll_queue_postback'  );
  $self->{POLL_QUEUE_POSTBACK} = $poll_queue_postback;
  my $poll_job_postback  = $session->postback( 'poll_job_postback'  );
  $self->{POLL_JOB_POSTBACK} = $poll_job_postback;
  $kernel->yield('poll_queue')
	if $self->{Q_INTERFACE}->can('ListQueue')
	&& $self->{POLL_QUEUE};
  $kernel->delay_set('poll_job',$self->{J_INTERVAL})
	if $self->{Q_INTERFACE}->can('ListJob');
  $kernel->yield('report_statistics') if $self->{STATISTICS_INTERVAL};
}

sub _child {}

sub shoot_myself
{
  my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];
  $kernel->call( $session, 'report_statistics' );
  if ( $self->{APMON} ) { $self->{APMON}->ApMon->free(); }
  $self->Logmsg("shooting myself...");
  $kernel->alarm_remove_all();
}

sub poll_queue
{
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];

  return unless $self->{POLL_QUEUE};
  $self->Logmsg('Why am I in poll_queue?') if $self->{DEBUG};
die "I do not want to be here...";
  $self->{JOBMANAGER}->addJob(
                             $self->{POLL_QUEUE_POSTBACK},
                             { LOGFILE => '/dev/null', TIMEOUT => $self->{Q_TIMEOUT}, KEEP_OUTPUT => 1 },
                             $self->{Q_INTERFACE}->Command('ListQueue')
                           );
}

sub poll_queue_postback
{
  my ( $self, $kernel, $arg0, $arg1 ) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
  my ($id,$result,$priority,$command);
die "This code has not been tested...";
  $command = $arg1->[0];
  $result  = $self->{Q_INTERFACE}->ParseListQueue( $command->{STDOUT} );

  if ( $self->{DEBUG} && $command->{DURATION} > 8 )
  {
    my $subtime = int(1000*$command->{DURATION})/1000;
    $self->Dbgmsg('ListQueue took ',$subtime,' seconds');
   }

  if ( $result->{ERROR} )
  {
    $self->Alert("ListQueue error: ",join("\n",@{$result->{ERROR}}));
    goto PQDONE;
  }
  else
  { $self->{LAST_SUCCESSFULL_POLL} = time; }

  foreach my $h ( values %{$result->{JOBS}} )
  {
    my $job;
    if ( ! exists($self->{JOBS}{$h->{ID}}) )
    {
      $job = PHEDEX::Transfer::Backend::Job->new
			(
			 ID		=> $h->{ID},
			 STATE		=> $h->{STATE},
			 SERVICE        => $h->{SERVICE},
			 TIMESTAMP	=> time,
			 VERBOSE	=> 1,
			);
    }
    else { $job = $self->{JOBS}{$h->{ID}}; }

# priority calculation here needs to be consistant with what is calculated
# later
    $priority = $self->{Q_INTERFACE}->StatePriority($h->{STATE});
    if ( ! $priority )
    {
#     I can forget about this job...
      $kernel->yield('report_job',$job);
      next;
    }

    if ( ! exists($self->{JOBS}{$h->{ID}}) )
    {
#     Queue this job for monitoring...
      $job->Priority($priority);
      $self->Dbgmsg('requeue(1) JOBID=',$job->ID) if $self->{DEBUG};
      $self->{QUEUE}->enqueue( $priority, $job );
      $self->{JOBS}{$h->{ID}} = $job;
      $self->Logmsg("Queued $h->{ID} at priority $priority (",$h->{STATE},")") if $self->{VERBOSE};
    }
  }
PQDONE:
  $kernel->delay_set('poll_queue', $self->{Q_INTERVAL});
}

sub poll_job
{
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
  my ($priority,$id,$job);

  ($priority,$id,$job) = $self->{QUEUE}->dequeue_next;
  if ( ! $id )
  {
    $self->{LAST_SUCCESSFUL_POLL} = time;
    $kernel->delay_set('poll_job', $self->{J_INTERVAL});
    return;
  }

  $self->Dbgmsg('dequeue JOBID=',$job->ID) if $self->{DEBUG};
  $self->{JOBMANAGER}->addJob(
                             $self->{POLL_JOB_POSTBACK},
                             { FTSJOB => $job, LOGFILE => '/dev/null', 
			       KEEP_OUTPUT => 1, TIMEOUT => $self->{Q_TIMEOUT} },
                             $self->{Q_INTERFACE}->Command('ListJob',$job)
                           );

}

sub poll_job_postback
{
  my ( $self, $kernel, $arg0, $arg1 ) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
  my ($result,$priority,$id,$job,$summary,$command,$error);

  $command = $arg1->[0];
  if ($command->{STATUS} ne "0") { 
      $error = "ended with status $command->{STATUS}";
      if ($command->{STDERR}) { 
	  $error .= " and error message: $command->{STDERR}"; 
      }
  }

  $job = $command->{FTSJOB};
  $result = $self->{Q_INTERFACE}->ParseListJob( $job, $command->{STDOUT} );

  if ( $self->{DEBUG} && $command->{DURATION} > 8 )
  {
    my $subtime = int(1000*$command->{DURATION})/1000;
    $self->Dbgmsg('ListJob took ',$subtime,' seconds');
  }

# Arbitrary value, fixed, for now.
  $priority = 30;
  if (exists $result->{ERROR}) {
      $error = join("\n",@{$result->{ERROR}});
  }

  # Log the monitoring command once when the job enters the queue, or on every error
  if ( $job->VERBOSE || $error )
  {
    # Log the command
    my $logsafe_cmd = join(' ', @{$command->{CMD}});
    $logsafe_cmd =~ s/ -p [\S]+/ -p _censored_/;
    $job->Log($logsafe_cmd);

    # Log any extra info
    foreach ( @{$result->{INFO}} ) { chomp; $job->Log($_) };
    
    # Log any error message
    foreach ( split /\n/, $command->{STDERR} ) { chomp;  $job->Log($_) };
    
    # Only do the verbose logging once
    $job->VERBOSE(0);
  };

  # Job monitoring failed
  if ($error) {
      $self->Alert("ListJob for ",$job->ID," returned error: $error\n");
  
#     If I haven't been successful monitoring this job for a long time, give up on it
      my $timeout = $job->Timeout;
      if ( $timeout && $job->Timestamp + $timeout < time  )
      {
        $self->Alert('Abandoning JOBID=',$job->ID," after timeout ($timeout seconds)");
        $job->State('abandoned');
	# If 'abandoned' is a terminal state for the job, set the state of all unfinished files
	# in the job to 'abandoned' as well. Else, let the job get back in the queue.
        if ( $job->ExitStates->{$job->State} )
        {
	    foreach ( keys %{$job->Files} ) {
		my $f = $job->Files->{$_};
		if ( $f->ExitStates->{$f->State} == 0 ) {
		    my $oldstate = $f->State('abandoned');
		    $f->Log($f->Timestamp,"from $oldstate to ",$f->State);
		    $f->Reason('Could not monitor transfer job');
		    # If 'abandoned' is a terminal state for the file, report it.
		    # Otherwise, reset the job state to undefined to let it get back in the queue.
		    if ( $f->ExitStates->{$f->State} ) {
			$job->FILE_POSTBACK->( $f, $oldstate, undef ) if $job->FILE_POSTBACK;
			$self->{FILE_POSTBACK}->( $f, $job ) if $self->{FILE_POSTBACK};
		    }
		    else {
			$job->State('undefined');
		    }
		} 
	    }
	}
    }
  }

  # Job monitoring was successful
  else {
      
      $self->{LAST_SUCCESSFULL_POLL} = time;
      $self->Logmsg("JOBID=",$job->ID," STATE=$result->{JOB_STATE}") if $self->{VERBOSE};
      
      $job->State($result->{JOB_STATE});
      $job->RawOutput(@{$result->{RAW_OUTPUT}});
      
      my $files = $job->Files;
      foreach ( keys %{$result->{FILES}} )
      {
	  my $s = $result->{FILES}{$_};
	  my $f = $files->{$s->{DESTINATION}};
	  if ( ! $f )
	  {
	      $f = PHEDEX::Transfer::Backend::File->new( %{$s} );
	      $job->Files($f);
	  }
	  
	  if ( ! exists $f->ExitStates->{$s->{STATE}} )
	  { 
	      my $last = $self->{_new_file_states}{$s->{STATE}} || 0;
	      if ( time - $last > 300 )
	      {
		  $self->{_new_file_states}{$s->{STATE}} = time;
		  $self->Alert("Unknown file-state: " . $s->{STATE});
	      }
	  }
	  
	  $self->WorkStats('FILES', $f->Destination, $f->State);
	  $self->LinkStats($f->Destination, $f->FromNode, $f->ToNode, $f->State);

	  if ( $_ = $f->State( $s->{STATE} ) )
	  {
	      $f->Log($f->Timestamp,"from $_ to ",$f->State);
	      $job->Log($f->Timestamp,$f->Source,$f->Destination,$f->State );
	      if ( $f->ExitStates->{$f->State} )
	      {
#       Log the details...
		  $summary = join (' ',
				   map { "$_=\"" . $s->{$_} ."\"" }
				   qw / SOURCE DESTINATION DURATION RETRIES REASON /
				   );
		  $job->Log( time, 'file transfer details',$summary,"\n" );
		  $f->Log  ( time, 'file transfer details',$summary,"\n" );
		  
		  foreach ( qw / DURATION RETRIES REASON / ) { $f->$_($s->{$_}); }
	      }
	      $job->FILE_POSTBACK->( $f, $_, $s ) if $job->FILE_POSTBACK;
	      $self->{FILE_POSTBACK}->( $f, $job ) if $self->{FILE_POSTBACK};
	  }
      }

      $summary = join(' ',
		      "ETC=" . $result->{ETC},
		      'JOB_STATE=' . $result->{JOB_STATE},
		      'FILE_STATES:',
		      map { $_.'='.$result->{FILE_STATES}{$_} }
		      sort keys %{$result->{FILE_STATES}}
		      );
      if ( $job->Summary ne $summary )
      {
	  $self->Logmsg('JOBID=',$job->ID," $summary") if $self->{VERBOSE};
	  $job->Summary($summary);
      }

      if ( ! exists $job->ExitStates->{$result->{JOB_STATE}} )
      { 
	  my $last = $self->{_new_job_states}{$result->{JOB_STATE}} || 0;
	  if ( time - $last > 300 )
	  {
	      $self->{_new_job_states}{$result->{JOB_STATE}} = time;
	      $self->Alert("Unknown job-state: " . $result->{JOB_STATE});
	  }
      }

      $job->State($result->{JOB_STATE});
  }

  $self->WorkStats('JOBS', $job->ID, $job->State);
  $self->{JOB_POSTBACK}->($job) if $self->{JOB_POSTBACK};
  if ( $job->ExitStates->{$job->State} )
  {
    $kernel->yield('report_job',$job);
  }
  else
  {
# Leave priority fixed for now.
#   $result->{ETC} = 100 if $result->{ETC} < 1;
#   $priority = $result->{ETC};
#   $priority = int($priority/60);
#   $priority = 30 if $priority < 30;
    $job->Priority($priority);
    $self->Dbgmsg('requeue(3) JOBID=',$job->ID) if $self->{DEBUG};
    $self->{QUEUE}->enqueue( $priority, $job );
  }

PJDONE:
  $kernel->delay_set('poll_job', $self->{J_INTERVAL});
}

sub report_job
{
  my ( $self, $kernel, $job ) = @_[ OBJECT, KERNEL, ARG0 ];
  my $jobid = $job->ID;
  $self->Logmsg("$jobid has ended in state ",$job->State) if $self->{VERBOSE};

  $job->Log(time,'Job has ended');
  $self->WorkStats('JOBS', $job->ID, $job->State);
  foreach ( values %{$job->Files} )
  {
    $self->WorkStats('FILES', $_->Destination, $_->State);
    $self->LinkStats($_->Destination, $_->FromNode, $_->ToNode, $_->State);
  }

  $self->{JOB_POSTBACK}->($job) if $self->{JOB_POSTBACK};
  if ( defined $job->JOB_POSTBACK ) { $job->JOB_POSTBACK->(); }
  else
  {
    $self->Dbgmsg('Log for ',$job->ID,"\n",
		  $job->Log,
		  "\n",'Log ends for ',$job->ID,"\n") if $self->{DEBUG};
  }

# Now I should take detailed action on any errors...
  $self->cleanup_job_stats($job);
  $kernel->delay_set('forget_job',900,$job);
}

sub forget_job
{
  my ( $self, $kernel, $job ) = @_[ OBJECT, KERNEL, ARG0 ];
  delete $self->{JOBS}{$job->ID} if $job->ID;
}

sub cleanup_job_stats
{
  my ( $self, $job ) = @_;
  my $jobid = $job->ID || 'unknown-job';
  $self->Logmsg("Cleaning up stats for JOBID=$jobid...") if $self->{VERBOSE};
  delete $self->{WORKSTATS}{JOBS}{STATES}{$jobid};
  foreach ( values %{$job->Files} )
  {
    $self->cleanup_file_stats($_);
  }
}

sub cleanup_file_stats
{
  my ( $self, $file ) = @_;
  $self->Logmsg("Cleaning up stats for file destination=",$file->Destination) if $self->{VERBOSE};
  delete $self->{WORKSTATS}{FILES}{STATES}{$file->Destination};
  delete $self->{LINKSTATS}{$file->Destination};
}

sub report_statistics
{
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
  my ($s,$t,$key,$summary);

  if ( ! defined($self->{WORKSTATS}{START}) )
  {
    $self->{WORKSTATS}{START} = time;
    $self->Logmsg("STATISTICS: INTERVAL=",$self->{STATISTICS_INTERVAL}) if $self->{VERBOSE};
  }
  $t = time - $self->{WORKSTATS}{START};

  foreach $key ( keys %{$self->{WORKSTATS}} )
  {
    next unless ref($self->{WORKSTATS}{$key}) eq 'HASH';
    next unless defined $self->{WORKSTATS}{$key}{STATES};
    $self->{WORKSTATS}{$key}{SUMMARY} = '' unless $self->{WORKSTATS}{$key}{SUMMARY};

    foreach ( keys %{$self->{WORKSTATS}{$key}{STATES}} )
    {
      $s->{$key}{TOTAL}++;
      $s->{$key}{STATES}{$self->{WORKSTATS}{$key}{STATES}{$_} || 'undefined'}++;
    }

    next unless defined( $s->{$key}{TOTAL} );
    $summary = join(' ', 'Total='.$s->{$key}{TOTAL},
    (map { "$_=" . $s->{$key}{STATES}{$_} } sort keys %{$s->{$key}{STATES}} ));
#   if ( $self->{WORKSTATS}{$key}{SUMMARY} ne $summary )
    {
      $self->Logmsg("STATISTICS: TIME=$t $key: $summary") if $self->{VERBOSE};
      $self->{WORKSTATS}{$key}{SUMMARY} = $summary;
    }

#    use Data::Dumper();
#    print "STATS DUMP: ", Data::Dumper::Dumper ($self->{STATS}), "\n"; # XXX

    if ( $self->{APMON} )
    {
      my $h = $s->{$key}{STATES};
      my $g;
      if ( $key eq 'JOBS'  ) { $g = PHEDEX::Transfer::Backend::Job::ExitStates(); }
      if ( $key eq 'FILES' ) { $g = PHEDEX::Transfer::Backend::File::ExitStates(); }
      foreach ( keys %{$g} )
      {
        $h->{$_} = 0 unless defined $h->{$_};
      }
      $h->{Cluster} = $self->{APMON}{Cluster} || 'PhEDEx';
      $h->{Node}    = ($self->{APMON}{Node} || $self->{ME}) . '_' . $key;
      $self->{APMON}->Send($h);
    }
  }

  $kernel->delay_set( 'report_statistics', $self->{STATISTICS_INTERVAL} );
}

sub WorkStats
{
  my ($self,$class,$key,$val) = @_;
  if ( defined($class) && !defined($key))
  {
      return $self->{WORKSTATS}{$class}{STATES};
  }
  elsif ( defined($class) && defined($key) )
  {
    $self->Dbgmsg("WorkStats: class=$class key=$key value=$val") if $self->{DEBUG};
    $self->{WORKSTATS}{$class}{STATES}{$key} = $val;
    return $self->{WORKSTATS}{$class};
  }
  return $self->{WORKSTATS};
}

sub LinkStats
{
    my ($self,$file,$from,$to,$state) = @_;
    return $self->{LINKSTATS} unless defined $file &&
				     defined $from &&
				     defined $to;
    $self->{LINKSTATS}{$file}{$from}{$to} = $state;
    return $self->{LINKSTATS}{$file}{$from}{$to};
}

sub isKnown
{
  my ( $self, $job ) = @_;
  return 0 unless defined $self->{JOBS}{$job->{ID}};
  return 1;
}

sub QueueJob
{
  my ( $self, $job, $priority ) = @_;

  return if $self->isKnown($job);
  $priority = 1 unless $priority;
  $self->Logmsg('Queueing JOBID=',$job->ID,' at priority ',$priority);

  $self->WorkStats('JOBS', $job->ID, $job->State);
  foreach ( values %{$job->Files} )
  {
    $self->WorkStats('FILES', $_->Destination, $_->State);
    $self->LinkStats($_->Destination, $_->FromNode, $_->ToNode, $_->State);
  }
  $job->Priority($priority);
  $job->Timestamp(time);
  $self->Dbgmsg('enqueue JOBID=',$job->ID) if $self->{DEBUG};
  $self->{QUEUE}->enqueue( $priority, $job );
  $self->{JOBS}{$job->{ID}} = $job;
}

1;
