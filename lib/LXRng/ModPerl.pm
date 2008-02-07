package LXRng::ModPerl;

use strict;
use LXRng;
use LXRng::Web;

use Apache2::Const -compile => qw(FORBIDDEN OK);
use CGI;

use Data::Dumper;

sub handler {
    my ($req) = @_;

    my $query = CGI->new();
    LXRng::Web->handle($query);

    return Apache2::Const::OK;
}

1;
