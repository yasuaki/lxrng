package LXRng::Repo::Plain;

use strict;
use LXRng::Repo::Plain::Iterator;
use LXRng::Repo::Plain::File;
use LXRng::Repo::Plain::Directory;

sub new {
    my ($class, $root) = @_;

    $root .= '/' unless $root =~ /\/$/;
    return bless({root => $root}, $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'root'};
}

sub allversions {
    my ($self) = @_;

    my @ver = (sort
	       grep { $_ ne "." and $_ ne ".." } 
	       map { substr($_, length($$self{'root'})) =~ /([^\/]*)/; $1 }
	       glob($$self{'root'}."*/"));

    return @ver;
}

sub node {
    my ($self, $path, $release) = @_;

    my $realpath = join('/', $$self{'root'}, $release, $path);
    return LXRng::Repo::Plain::File->new($path, $realpath);
}

sub iterator {
    my ($self, $release) = @_;

    return LXRng::Repo::Plain::Iterator->new($self->node('', $release));
}

1;
