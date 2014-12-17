package PHEDEX::LoadTest::Injector::Agent;
use strict;
use warnings;
use base 'PHEDEX::Core::Agent', 'PHEDEX::Core::Logging';
use PHEDEX::Core::Timing;
use PHEDEX::Core::DB;

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);
    my %params = (DBCONFIG => undef,		# Database configuration file
		  MYNODE => undef,		# My TMDB node
		  ONCE => 0,			# Quit after one run
		  WAITTIME => 60*20,            # Agent cycle time
		  VISION => 3600*6);            # Agent vision time (past and present)
    my %args = (@_);
    map { $$self{$_} = $args{$_} || $params{$_} } keys %params;
    bless $self, $class;
    return $self;
}

# Called by agent main routine before sleeping.  Do some work.
sub idle
{
    my ($self, @pending) = @_;
    
    $self->Logmsg("starting injections");

    eval {
	$self->connectAgent();
	
	# Get the LoadTest parameters for every link
	my $qparam = &dbexec($$self{DBH}, qq{
	    select lp.src_dataset, ds.name src_dataset_name,
	           lp.dest_dataset, dd.name dest_dataset_name,
	           lp.dest_node, dn.name dest_node_name,
	           lp.is_active, lp.dataset_size, lp.dataset_close,
	           lp.block_size, lp.block_close,
	           lp.rate, lp.inject_now,
	           lp.throttle_node, tn.name throttle_node_name,
	           lp.time_inject
	      from t_loadtest_param lp
	      join t_dps_dataset ds on ds.id = lp.src_dataset
	      join t_dps_dataset dd on dd.id = lp.dest_dataset
	      join t_adm_node dn on dn.id = lp.dest_node
	 left join t_adm_node tn on tn.id = lp.throttle_node
	    });
    
	my $uparam = &dbprep($$self{DBH}, qq{
	    update t_loadtest_param set inject_now = 0, time_inject = :time_inject
   	     where src_dataset = :src_dataset
	       and dest_dataset = :dest_dataset
	       and dest_node = :dest_node});
             
	my $total_inject = 0;
	while (my $params = $qparam->fetchrow_hashref()) {
	    $$params{NOW} = &mytimeofday();

	    next unless $$params{IS_ACTIVE} eq 'y';
	    next unless $self->datasetSpace($params);
	    
	    my $size = $self->averageFileSize($$params{SRC_DATASET});
	    unless ($size) {
		$self->Alert("dataset=$$params{SRC_DATASET} has no files");
		next;
	    }
	    
	    my $n_files = 0;
	    if ($$params{INJECT_NOW}) {
		$n_files = $$params{INJECT_NOW};
	    } elsif ($$params{RATE}) {
		$n_files = $self->calculateRateInjection($params, $size);

		my $t_files = $self->throttleNodeFiles($params);
		my $throttle = ($t_files * $size > $$params{RATE} * $$self{VISION}) ? 1 : 0;
		if ($n_files != 0 && $throttle) {
		    &dbbindexec($uparam, 
				':time_inject' => $$params{NOW},
				':src_dataset' => $$params{SRC_DATASET},
				':dest_dataset' => $$params{DEST_DATASET},
				':dest_node' => $$params{DEST_NODE}
				);
		    $self->{DBH}->commit();
		    $self->Logmsg("skipped injections to dataset $$params{DEST_DATASET_NAME} at $$params{DEST_NODE_NAME}:  ",
			    "throttle node $$params{THROTTLE_NODE_NAME} has enough to do with $t_files files");
		    next;
		}
	    } else {
		next; # Nothing to do
	    }
	
	    next unless $n_files;

	    # Transaction per dataset.  Rollback and continue in case of any errors
	    eval
	    {
		my $n_inject = $self->injectFiles($params, $n_files);
		if ($n_inject) {
		    &dbbindexec($uparam, 
				':time_inject' => $$params{NOW},
				':src_dataset' => $$params{SRC_DATASET},
				':dest_dataset' => $$params{DEST_DATASET},
				':dest_node' => $$params{DEST_NODE}
				);
		    
		    $$self{DBH}->commit();
		    $self->Logmsg("injected $n_inject files to dataset ",
			    "$$params{DEST_DATASET_NAME} at $$params{DEST_NODE_NAME}");
		    $total_inject += $n_inject;
		} else {
		    $$self{DBH}->rollback();
		    die "no files injected to dataset $$params{DEST_DATASET_NAME} at ",
		    "$$params{DEST_NODE_NAME}, tried to inject $n_files\n";
		}
	    };
	    if ($@) {
		chomp ($@);
		$self->Alert("database error: $@");
		$$self{DBH}->rollback();
	    }
	}
	
	$self->Logmsg("finished injections:  $total_inject files injected");
		
    };
    do { chomp ($@); $self->Alert ("database error: $@");
	 eval { $$self{DBH}->rollback() } if $$self{DBH} } if $@;

    # Disconnect from the database
    $self->disconnectAgent();    

    $self->doStop() if $$self{ONCE};
}


sub datasetSpace
{
    my ($self, $params) = @_;

    my $ds_size = defined $$params{DATASET_SIZE} ? $$params{DATASET_SIZE} : POSIX::FLT_MAX;

    my $info = &dbexec($$self{DBH}, qq{
	select ds.id, ds.is_open, count(b.id) n_blocks
          from t_dps_dataset ds
     left join t_dps_block b on b.dataset = ds.id
         where ds.id = :dataset
         group by ds.id, ds.is_open},
    ':dataset' => $$params{DEST_DATASET})->fetchrow_hashref();

    # Full if the dataset is closed or the number of blocks is more than the limit
    return 0 if ($$info{IS_OPEN} eq 'n' || $$info{N_BLOCKS} > $ds_size);
		       
    # If we are at the limit, we need to check if the last block is full
    if ($$info{N_BLOCKS} == $ds_size) {
	my $n = $self->lastBlockSpace($params);
	if (defined $n && $n == 0) {
	    return 0;
	} else {
	    return 1;
	}
    }

    # Dataset isn't full, return the number of blocks left
    return $ds_size - $$info{N_BLOCKS};
}

sub getLastBlock
{
    my ($self, $params) = @_;

    # Query the last block, being careful only to get blocks with the LoadTest syntax
    # Also parses and returns the block number (e.g. /foo/bar/blah#123 is block number 123)
    my $info = &dbexec($$self{DBH}, q{
	select b.id, b.name, b.is_open, b.files, regexp_replace(b.name, '.*#(\d+)$', '\1') block_number from (
	  select * from t_dps_block where dataset = :dataset and regexp_like(name, '#\d+$')
           order by id desc ) b where rownum = 1
       }, ':dataset' => $$params{DEST_DATASET})->fetchrow_hashref();

    return $info;
}

sub lastBlockSpace
{
    my ($self, $params, $lock) = @_;

    my $info = $self->getLastBlock($params);

    # !!! Possible race condition here...  is there a way to select
    # the last block and lock it at the same time?  "for update" not
    # allowed in above query
    &dbexec($$self{DBH}, qq{ select id from t_dps_block where id = :block for update },
	    ':block' => $$info{ID}) if exists $$info{ID} && $lock;

    my $n_left;
    if (!exists $$info{ID}) {
	# Return undefined if there is no last block
	return (undef, undef);
    } elsif ($$info{IS_OPEN} eq 'n') {
	# Return 0 if the last block is closed
	$n_left = 0;
    } elsif (!defined $$params{BLOCK_SIZE}) {
	# Return a huge number if the blocks can be of infinite size
	$n_left = POSIX::DBL_MAX;
    } else {
	# Return how much there is left
	$n_left = $$params{BLOCK_SIZE} - $$info{FILES};
    }
    
    $n_left = 0 if $n_left < 0;

    return wantarray ? ($n_left, $info) : $n_left;
}

sub throttleNodeFiles
{
    my ($self, $params) = @_;
    return 0 unless ($$params{THROTTLE_NODE});
    my ($t_files) = &dbexec($$self{DBH}, qq{
      select sum(b.files) - sum(nvl(br.node_files,0))
        from t_dps_dataset ds 
        join t_dps_block b on b.dataset = ds.id
   left join t_dps_block_replica br on br.block = b.id and br.node = :throttle_node
   where ds.id = :dataset },
			    ':dataset' => $$params{DEST_DATASET},
			    ':throttle_node' => $$params{THROTTLE_NODE})->fetchrow();
    
    return $t_files || 0;
}

sub averageFileSize
{
    my ($self, $dataset) = @_;
    return unless $dataset;
    # Get the average
    my ($size) = &dbexec($$self{DBH}, qq{
	select avg(f.filesize) from t_dps_file f
	    join t_dps_block b on b.id = f.inblock
	    join t_dps_dataset ds on ds.id = b.dataset
	    where ds.id = :dataset },
			 ':dataset' => $dataset)->fetchrow();

    return $size;
}

sub calculateRateInjection
{
    my ($self, $params, $size) = @_;

    return 0 unless $size;

    # If this is the first injection, inject one file
    if (!$$params{TIME_INJECT}) {
	return 1;
    }

    my $delta_t = $$params{NOW} - $$params{TIME_INJECT};

    # If it has been over the vision time since our last injection, don't try to
    # "catch-up" the rate.  Just insert one file and we'll continue
    # the rate from there
    if ($delta_t > $$self{VISION}) {
	return 1;
    }

    my $n_files = ($delta_t * $$params{RATE}) / $size;
    
    # We return a number that at least meets the target rate
    return $n_files > 1 ? POSIX::ceil($n_files) : 0;
}

sub injectFiles
{
    my ($self, $params, $n_files) = @_;

    my $src_lfns = $self->getSourceLFNs($params);
    return 0 unless @$src_lfns;

    my @files;

    # get the space left in the last block and get files to fill it
    my ($b_space, $last_block) = $self->lastBlockSpace($params, 1); # also locks block
    while (defined $last_block && $b_space > 0 && $n_files > 0) {
	push @files, $self->pickNewLFN($params, $src_lfns, $last_block);
	$b_space--; $n_files--;
    }

    # close the last block if we filled it
    $self->closeBlock($$last_block{ID}) if defined $last_block && $$params{BLOCK_CLOSE} eq 'y' && $b_space == 0;

    # create new blocks needed and fill them with files
    my $n_blocks = POSIX::ceil($n_files / $$params{BLOCK_SIZE});
    my $ds_space = $self->datasetSpace($params);
    $n_blocks = $ds_space if $n_blocks > $ds_space;

    my $close_last = $n_files % $$params{BLOCK_SIZE} == 0 ? 1 : 0;
    my @new_blocks = $self->createNewBlocks($params,
					    defined $last_block ? $$last_block{BLOCK_NUMBER} : 0,
					    $n_blocks, $close_last);

    foreach my $block (@new_blocks) {
	last if $n_files == 0;
	$b_space = $$params{BLOCK_SIZE};
	while ($b_space > 0 && $n_files > 0) {
	    push @files, $self->pickNewLFN($params, $src_lfns, $block);
	    $b_space--; $n_files--;
	}
	$ds_space--;
    }

    # execute a bulk injection
    my $n_inject = $self->injectFileArray(\@files);

    # close full datasets
    $self->closeDataset($$params{DEST_DATASET}) if $$params{DATASET_CLOSE} eq 'y' && $ds_space == 0 && $b_space == 0;
    
    return $n_inject;
}

sub closeBlock
{
    my ($self, $block) = @_;
    return unless defined $block

	&dbexec($$self{DBH}, qq{
	    update t_dps_block set is_open = 'n' where id = :block },
		':block' => $block);
}

sub closeDataset
{
    my ($self, $dataset) = @_;
    return unless defined $dataset;

    &dbexec($$self{DBH}, qq{
	update t_dps_block set is_open = 'n' where dataset = :dataset },
	    ':dataset' => $dataset);

    &dbexec($$self{DBH}, qq{
	update t_dps_dataset set is_open = 'n' where id = :dataset },
	    ':dataset' => $dataset);
}

sub createNewBlocks
{
    my ($self, $params, $start_n, $n_blocks, $close_last) = @_;

    my @blocks;

    my $ins_b =	&dbprep($$self{DBH}, qq{
	insert into t_dps_block (id, dataset, name, files, bytes, is_open, time_create)
	    values (seq_dps_block.nextval, :dataset, :name, 0, 0, :is_open, :now)
	    returning id into :id });

    my $n = $start_n;

    for (1 .. $n_blocks) {
	$n++;
	my $block = {};
	$$block{NAME} = $$params{DEST_DATASET_NAME} . "#" . $n;
	$$block{BLOCK_NUMBER} = $n;
	# we close all the blocks except the last one, unless asked to
	$$block{IS_OPEN} = $$params{BLOCK_CLOSE} eq 'y' && ($_ != $n_blocks || $close_last) ? 'n' : 'y';

	&dbbindexec($ins_b, ':dataset' => $$params{DEST_DATASET},
		    ':name' => $$block{NAME},
		    ':is_open' => $$block{IS_OPEN},
		    ':now' => $$params{NOW},
		    ':id' => \$$block{ID});

	push @blocks, $block;
    }
    
    return @blocks;
}

sub injectFileArray
{
    my ($self, $files) = @_;
    
    return unless @$files;

    my $idps = &dbprep($$self{DBH}, qq{
	insert into t_dps_file
	    (id, node, inblock, logical_name, checksum, filesize, time_create)
	    values (seq_dps_file.nextval, ?, ?, ?, ?, ?, ?)});
    my $ixfer = &dbprep($$self{DBH}, qq{
	insert into t_xfer_file
	    (id, inblock, logical_name, checksum, filesize)
	    (select id, inblock, logical_name, checksum, filesize
	     from t_dps_file where logical_name = ?)});
    my $ixr = &dbprep($$self{DBH}, qq{
	insert into t_xfer_replica
	    (id, fileid, node, state, time_create, time_state)
	    (select seq_xfer_replica.nextval, id, ?, 0, ?, ?
	     from t_xfer_file where logical_name = ?)});

    my (%dps, %xfer, %xr);
    foreach my $file (@$files)
    {
	my $n = 1;
	push(@{$dps{$n++}}, $$file{SOURCE});
	push(@{$dps{$n++}}, $$file{BLOCK});
	push(@{$dps{$n++}}, $$file{LFN});
	push(@{$dps{$n++}}, $$file{CHECKSUM});
	push(@{$dps{$n++}}, $$file{FILESIZE});
	push(@{$dps{$n++}}, $$file{TIME_CREATE});
	
	$n = 1;
	push(@{$xfer{$n++}}, $$file{LFN});

	$n = 1;
	push(@{$xr{$n++}}, $$file{SOURCE});
	push(@{$xr{$n++}}, $$file{TIME_CREATE});
	push(@{$xr{$n++}}, $$file{TIME_CREATE});
	push(@{$xr{$n++}}, $$file{LFN});		
    }
    
    &dbbindexec($idps, %dps);
    &dbbindexec($ixfer, %xfer);
    &dbbindexec($ixr, %xr);
    
    return scalar @$files;
}

sub getSourceLFNs
{
    my ($self, $params) = @_;

    # Get LFNs which are only really in the source and at the node.
    # We have to check also for collapsed blocks because the source
    # datasets may not have moved for a long time
    my $q = &dbexec($$self{DBH}, qq{
	select xf.id, xf.logical_name lfn, xf.filesize, xf.checksum
	 from t_xfer_file xf
         join t_xfer_replica xr on xr.fileid = xf.id
	 join t_dps_block b on b.id = xf.inblock
	 join t_dps_dataset ds on ds.id = b.dataset
        where ds.id = :dataset1 and xr.node = :node1
        union
       select f.id, f.logical_name lfn, f.filesize, f.checksum
         from t_dps_file f
         join t_dps_block b on b.id = f.inblock
         join t_dps_block_replica br on br.block = b.id
         join t_dps_dataset ds on ds.id = b.dataset
        where ds.id = :dataset2 and br.node = :node2
	and br.is_active = 'n' },
		    ':dataset1' => $$params{SRC_DATASET},
		    ':dataset2' => $$params{SRC_DATASET},
		    ':node1' => $$params{DEST_NODE},
		    ':node2' => $$params{DEST_NODE});
    
    my $lfns = [];
    while (my $lfn = $q->fetchrow_hashref()) {
	push @$lfns, $lfn;
    }
	 
    $self->Alert("source dataset=$$params{SRC_DATASET} has no files at node=$$params{DEST_NODE}") unless @$lfns;
    return $lfns;
}

sub pickNewLFN
{
    my ($self, $params, $src_lfns, $block) = @_;
    
    # Pick a random LFN from the source set
    my $lfn = $$src_lfns[ int(rand @$src_lfns) ];
    $lfn = { %$lfn }; # copy

    # Generate a useful LFN
    if ($$params{SRC_DATASET_NAME} =~ m:LoadTest07Source:) {
	# Special compatability for OLD LoadTest07 naming conventions
	# TODO:  Remove this condition when we don't need compatibility anymore.
	# The naming convention for src_dataset of the old samples will be:
	#   dataset /PhEDEx_Debug/LoadTest07Source/CERN
	#   block   /PhEDEx_Debug/LoadTest07Source/CERN#block
	#   file    /store/PhEDEx_Debug/LoadTest07Source/CERN_01
	# The naming convention for dest_dataset needs to be like:
	#   dataset /PhEDEx_Debug/LoadTest07_CERN/ASGC
	#   block   /PhEDEx_Debug/LoadTest07_CERN_ASGC#0
	#   file    /store/PhEDEx_LoadTest07/LoadTest07_Debug_CERN/ASGC/0/LoadTest07_CERN_0B_7OmAuGqR_0
	my ($src_id) = ( $$lfn{LFN} =~ m:/([^/]+)$: );
	my $dname = $$params{DEST_DATASET_NAME};
	$dname =~ s:PhEDEx_(.*)/LoadTest07:PhEDEx_LoadTest07/LoadTest07_$1:;
	$$lfn{LFN} = "/store$dname/" . $$block{BLOCK_NUMBER} . 
	    '/LoadTest07_' . $src_id . '_' . &makeGUID() . '_' . $$block{BLOCK_NUMBER};
    } else {
	# A simpler pattern:
	#  {sourceLFN}.LTgenerated/{destNode}/{destDataset}/{destBlockNum}/{GUID}
	#  directory depth is sourceLFN_depth + 5
	#  largest directory is {destBlockNum} (configurable, goes to infinity if BLOCK_SIZE is infinite)
	#                    or {destDataset}  (goes to infinity if DATASET_SIZE is infinite)
	#  Removing everything after and including .LTgenerated gets you back to the original LFN
	$$lfn{LFN} .= join("/", ".LTgenerated",
			   $$params{DEST_NODE_NAME},
			   $$params{DEST_DATASET_NAME},
			   $$block{BLOCK_NUMBER},
			   &makeGUID()
			   );
	$$lfn{LFN} =~ s:/+:/:g; # remove double slashes //
    }

    # Associate new block and source
    $$lfn{BLOCK} = $$block{ID};
    $$lfn{SOURCE} = $$params{DEST_NODE};
    $$lfn{TIME_CREATE} = $$params{NOW};

    return $lfn;
}


sub makeGUID
{
    my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9);
    return join("", @chars[ map { rand @chars } ( 1 .. 16 )]);
}

1;
