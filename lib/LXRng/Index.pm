package LXRng::Index;

use strict;

sub transaction(&@) {
    my ($code, $index) = @_;

    $index->transaction($code);
}

1;
