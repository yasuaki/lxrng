package LXRng::Repo::Directory;

use strict;

sub name {
    my ($self) = @_;

    return $$self{'name'};
}

sub node {
    my ($self) = @_;

    $self->name =~ m,([^/]+)/?$, and return $1;
}

1;
