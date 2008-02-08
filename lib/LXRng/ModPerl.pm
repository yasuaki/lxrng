# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The full GNU General Public License is included in this distribution
# in the file called COPYING.

package LXRng::ModPerl;

use strict;
use LXRng;
use LXRng::Web;

use Apache2::Const -compile => qw(FORBIDDEN OK);
use CGI;

use Data::Dumper;

sub handler {
    my ($req) = @_;

    my @tstart = times();
    my $query  = CGI->new();
    my $qident = LXRng::Web->handle($query);
    my @tstop  = times();

    $req->notes->add("lxr_prof" =>
		     sprintf("u:%d, s:%d, cu:%d, cs:%d",
			     map { 1000*($tstop[$_]-$tstart[$_]) } (0 .. 3)));
    $req->notes->add("lxr_ident" => $qident);

    return Apache2::Const::OK;
}

1;
