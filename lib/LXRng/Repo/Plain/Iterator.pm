package LXRng::Repo::Plain::Iterator;

use strict;
use LXRng::Repo::Plain;

sub new {
    my ($class, $dir) = @_;

    return bless({dir => $dir, stack => [], nodes => [$dir->contents]}, $class);
}

sub next {
    my ($self) = @_;

    while (@{$$self{'nodes'}} == 0) {
	return undef unless @{$$self{'stack'}};
	$$self{'nodes'} = pop(@{$$self{'stack'}});
    }
    
    my $node = shift(@{$$self{'nodes'}});
    if ($node->isa('LXRng::Repo::Directory')) {
	push(@{$$self{'stack'}}, $$self{'nodes'});
	$$self{'nodes'} = [$node->contents];
	return $self->next;
    }
    return $node;
}

1;
