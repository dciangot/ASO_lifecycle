package PHEDEX::Namespace::dpm::delete;
# Implements the 'delete' function for posix access
use strict;
use warnings;
use base 'PHEDEX::Namespace::dpm::Common';

sub new
{
  my ($proto,$h) = @_;
  my $class = ref($proto) || $proto;
# $self is an empty hashref because there is no external command to call
  my $self = { cmd => 'rfrm',opts => []};
  bless($self, $class);
  $self->{ENV} = $h->{ENV} || '';
  return $self;
}

sub execute { (shift)->SUPER::execute(@_,'delete'); }

#sub execute
#{
# Deletes an array of files. Returns the difference between the number of
# files to be deleted and the number actually deleted. I.e. returns 0 for
# success, regardless of the number of files it is given
#die "Until someone verifies that this code works, I die here. Wanna fix the code...?\n";
#  my ($self,$ns,@files) = @_;
#  return 0 unless @files;
#  return scalar @files - unlink @files;
#}

sub Help
{
  print <<EOH;
delete (unlink) a set of files. Returns the number of files _not_
deleted. This allows you to call it with an empty list and still make sense
of the return value
EOH
  print "N.B. This code is not tested, and will die() if you try to use it.\n";
}

1;
