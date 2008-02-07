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

package LXRng::Lang::Undefined;

use strict;
use Subst::Complex;

use base qw(LXRng::Lang::Generic);


sub doindex {
    return 0;
}

sub pathexp {
    return qr/$/;
}

sub reserved { 
    return {};
}

sub parsespec {
    return ['atom',	'\\\\.',	undef];
}

sub typemap {
    return {};
}

sub markuphandlers {
    my ($self, $context, $node, $markup) = @_;
    
    my $format_newline = $markup->make_format_newline($node);

    my %subst;
    $subst{'code'} = new Subst::Complex
	qr/\n/ => $format_newline,
	qr/[^\n]*/ => sub { $markup->format_raw(@_) };

    $subst{'start'} = new Subst::Complex
	qr/^/  => $format_newline;

    return \%subst;
}

1;
