package PHEDEX::CLI::Inject;
use Getopt::Long;
use Data::Dumper;
use strict;
use warnings;

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my ($help,%params,%options);
  %params = (
	      VERBOSE	=> 0,
	      DEBUG	=> 0,
	      STRICT	=> 1,
	      DATAFILE	=> undef,
	      NODE	=> undef,
	    );
  %options = (
               'help'		=> \$help,
	       'verbose!'	=> \$params{VERBOSE},
	       'debug'		=> \$params{DEBUG},
	       'strict!'	=> \$params{STRICT},
	       "datafile=s@"	=> \$params{DATAFILE},
	       "node=s"		=> \$params{NODE},
	     );
  GetOptions(%options);
  my $self = \%params;
  print "I am in ",__PACKAGE__,"->new()\n" if $self->{VERBOSE};

  bless $self, $class;
  $self->Help() if $help;
  return $self;
}

sub AUTOLOAD
{
  my $self = shift;
  my $attr = our $AUTOLOAD;
  $attr =~ s/.*:://;
  if ( exists($self->{$attr}) )
  {
    $self->{$attr} = shift if @_;
    return $self->{$attr};
  } 
}

sub Help
{
  print "\n Usage for ",__PACKAGE__,"\n";
  die <<EOF;

 This command accepts one or more XML datafiles for uploading to a dataservice,
and uses the dataservice to inject them into PhEDEx at a given node.

 Options:
 --datafile <filename>	name of an xml file. May be repeated, in which case the
			file contents are concatenated. The xml format is
			specified on the PhEDEx twiki on the 'Machine
			Controlled Subscriptions' project page
 --node <nodename>	name of the node this data is to be injected at.
 --(no)strict		is passed to the server for the injection call.

 ...and of course, this module takes the standard options:
 --help, --(no)debug, --(no)verbose
 --verbose		is also passed to the server for the injection call.

EOF
}

sub Payload
{
  my $self = shift;
  my $payload;

  die __PACKAGE__," no datafiles given\n" unless $self->{DATAFILE};
  die __PACKAGE__," no node given\n" unless $self->{NODE};

  foreach ( qw / NODE STRICT / ) { $payload->{lc $_} = $self->{$_}; }
  foreach ( @{$self->{DATAFILE}} )
  {
    open DATA, "<$_" or die "open: $_ $!\n";
    $payload->{data} .= join('',<DATA>);
    close DATA;
    $payload->{data} =~ s%</data>\n<data>%%;
  }

  foreach ( qw / nodeid result stats / ) { $payload->{$_} = undef; }
  print __PACKAGE__," created payload\n" if $self->{VERBOSE};
  return $self->{PAYLOAD} = $payload;
}

sub Call { return 'Inject'; }

sub ResponseIsValid
{
# assume the response is in Perl Data::Dumper format!
  my ($self, $obj) = @_;
  my $payload  = $self->{PAYLOAD};

  my $stats = $obj->{PHEDEX}{INJECT}{STATS};
  if ( !defined $stats || ref($stats) ne 'HASH' ) { return 0; }

  print __PACKAGE__," response is valid\n" if $self->{VERBOSE};
  return 1;
}

sub Dump { return Data::Dumper->Dump([ (shift) ],[ __PACKAGE__ ]); }

sub Report
{
  my ($self, $obj) = @_;

  my $stats = $obj->{PHEDEX}{INJECTED}{STATS};
  foreach my $stat (sort keys %$stats) {
      print "$stat\t:\t$stats->{$stat}\n";
  }

}

1;
