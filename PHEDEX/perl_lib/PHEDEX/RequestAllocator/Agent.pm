package PHEDEX::RequestAllocator::Agent;

use strict;
use warnings;

use base 'PHEDEX::Core::Agent', 'PHEDEX::Core::Logging', 
    'PHEDEX::RequestAllocator::Core', 'PHEDEX::RequestAllocator::SQL';

use PHEDEX::Core::Timing;

our %params =
	(
	  MYNODE => undef,              # my TMDB nodename
    	  DBCONFIG => undef,		# Database configuration file
	  WAITTIME => 15*60,            # Agent cycle time
	  VERBOSE    => $ENV{PHEDEX_VERBOSE} || 0,
	  ME	     => 'RequestAllocator',
	);

our @array_params = qw / MYARRAY /;
our @hash_params  = qw / MYHASH /;

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = $class->SUPER::new(%params,@_);
  bless $self, $class;
  return $self;
}

sub AUTOLOAD
{
  my $self = shift;
  my $attr = our $AUTOLOAD;
  $attr =~ s/.*:://;
  if ( exists($params{$attr}) )
  {
    $self->{$attr} = shift if @_;
    return $self->{$attr};
  }
  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  my $parent = "SUPER::" . $attr;
  $self->$parent(@_);
}

sub init
{
  my $self = shift;

  print $self->Hdr,"entering init\n";
# base initialisation
  $self->SUPER::init(@_);

# Now my own specific values...
  $self->SUPER::init
	(
	  ARRAYS => [ @array_params ],
	  HASHES => [ @hash_params ],
	);
  print $self->Hdr,"exiting init\n";
}

sub idle
{
  my $self = shift;
  my $dbh;

  my %stats = ( request => 0,
		dataset => 0,
		block   => 0 );


  eval
  {
    $dbh = $self->connectAgent();
    my $now = &mytimeofday ();
    
   
    # Get transfer requests which need to be re-evaluated
    # Pending transfer requests with wildcards
    my $xfer_reqs = $self->getTransferRequests( PENDING  => 1,
                                                STATIC    => 0,
                                                WILDCARDS => 1,
                                                DEST_ONLY => 1
                                                );
    
    # Approved transfer requests with wildcards
    my $approved_xfer_reqs = $self->getTransferRequests( APPROVED  => 1,
						STATIC    => 0,
						WILDCARDS => 1,
						DEST_ONLY => 1
						);

    @{$xfer_reqs}{ keys %$approved_xfer_reqs } = values %$approved_xfer_reqs;

    # Expand each request into subscriptions
    foreach my $xreq ( values %$xfer_reqs ) {
	if (! $xreq->{DBS_ID} ) {
	    $self->Dbgmsg("skipping request $xreq->{ID}:  null DBS id") if $self->{DEBUG};
	    next;
	}

#	Sanity check on custodiality
	if (! $xreq->{IS_CUSTODIAL} ) {
	    $self->Dbgmsg("skipping request $xreq->{ID}:  null IS_CUSTODIAL") if $self->{DEBUG};
	    next;
	}

	$stats{request}++;
	# Filter only destination nodes where the request has been approved
	my $dest_nodes = [ grep {$xreq->{NODES}->{$_}->{DECISION} &&
				     $xreq->{NODES}->{$_}->{DECISION} eq 'y'} keys %{ $xreq->{NODES} } ];
	my ($datasets, $blocks) = $self->expandDataClob( $xreq->{DBS_ID}, $xreq->{DATA} );

	# Find all the data we need to skip
	my ($ex_ds, $ex_b) = $self->getExistingRequestData( $xreq->{ID} );
	my $skip = { DATASET => { map { $_ => 1 } @$ex_ds },
		     BLOCK   => { map { $_ => 1 } @$ex_b } };
	foreach my $items ( [ 'DATASET', $datasets ], [ 'BLOCK', $blocks ] ) {
	    my ($type, $ids) = @$items;
	    my @new;
	    while (my $id = shift @$ids) {
		if (exists $skip->{$type}->{$id}) {  # skip if exists
		    # do nothing
		    $self->Dbgmsg("skipping existing $type $id for request $xreq->{ID}") if $self->{DEBUG};
		} else {                             # otherwise add to req data table
		    $self->Dbgmsg("adding new $type $id for request $xreq->{ID}") if $self->{DEBUG};
		    $self->addRequestData( $xreq->{ID}, $type => $id );
		    push @new, $id;
		}
	    }
	    @$ids = @new;
	}

	
	# everything left in $datasets, $blocks is new data items
	# for approved requests, distribute these among the nodes
	my $subscribe = $self->distributeData( NODES => $dest_nodes,
					       DATASETS => $datasets,
					       BLOCKS => $blocks );

	foreach my $subn ( @$subscribe ) {
	    my ($type, $node, $id) = @$subn;
	    
	    $self->Logmsg("adding subscription parameter set from request=$xreq->{ID}");                                                  
	    # Create new original parameter set, or retrieve old one if existing
	    my $rparam = $self->createSubscriptionParam (
							 REQUEST => $xreq->{ID},
							 PRIORITY => $xreq->{PRIORITY},
							 IS_CUSTODIAL => $xreq->{IS_CUSTODIAL},
							 USER_GROUP => $xreq->{USER_GROUP},
							 ORIGINAL => 1,
							 TIME_CREATE => $now
							 );
	    $self->Logmsg("adding subscription ",lc $type, "=$id for node=$node from request=$xreq->{ID}");
	    my $n_subs = $self->createSubscription( $type => $id,
						    DESTINATION => $node, 
						    IS_MOVE => $xreq->{IS_MOVE},
						    TIME_START => $xreq->{TIME_START},
						    TIME_CREATE => $now,
						    SKIP_DUPLICATES => 1,
						    PARAM => $rparam
						    );
	    $stats{lc $type} += $n_subs if $n_subs;
	    
	}
	
	$self->execute_commit();
	delete $xfer_reqs->{ $xreq->{ID} }; # free some memory
	$self->maybeStop();
    }
  };
  do { chomp ($@); $self->Alert ("database error: $@");
       eval { $dbh->rollback() } if $dbh; } if $@;

  $self->Logmsg("evaluated $stats{request} requests: ",
		($stats{dataset} || $stats{block} ? 
		 "subscribed $stats{dataset} datasets and $stats{block} blocks"
		 : "nothing to do"));
      # Disconnect from the database
    $self->disconnectAgent();
}

sub isInvalid
{
  my $self = shift;
  my $errors = 0;
  print $self->Hdr,"entering isInvalid\n" if $self->{VERBOSE};
  print $self->Hdr,"exiting isInvalid\n" if $self->{VERBOSE};

  return $errors;
}

1;
