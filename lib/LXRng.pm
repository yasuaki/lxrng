package LXRng;

use strict;
use vars qw($ROOT);

sub import {
    my ($class, %args) = @_;

    $ROOT = $args{'ROOT'} if exists $args{'ROOT'};
}

1;
