package LXRng::Repo::Plain::File;

use strict;

use base qw(LXRng::Repo::File);
use Fcntl;

sub new {
    my ($class, $name, $path) = @_;

    my @stat = stat($path);

    return undef unless @stat;

    return LXRng::Repo::Plain::Directory->new($name, $path, \@stat) if -d _;

    return bless({name => $name, path => $path, stat => \@stat}, $class);
}

sub time {
    my ($self) = @_;

    return $$self{'stat'}[9];
}

sub size {
    my ($self) = @_;

    return $$self{'stat'}[7];
}

sub phys_path {
    my ($self) = @_;

    return $$self{'path'};
}

sub revision {
    my ($self) = @_;

    return $self->time.'.'.$self->size;
}

sub handle {
    my ($self) = @_;

    sysopen(my $handle, $self->phys_path, O_RDONLY) or die($!);
    return $handle;
}

1;
