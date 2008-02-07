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

package LXRng::Lang;

use strict;
use vars qw(@languages %deftypes %defweight);


%deftypes = 
    (
     'c' => 'class',
     'd' => 'macro (un)definition',
     'e' => 'enumerator',
     'f' => 'function',
     'g' => 'enumeration name',
     'm' => 'class, struct, or union member',
     'n' => 'namespace',
     'p' => 'function prototype or declaration',
     's' => 'structure',
     't' => 'typedef',
     'u' => 'union',
     'v' => 'variable',
     'l' => 'local variable',
     'x' => 'extern or forward variable declaration',
     'i' => 'interface'
     );

%defweight = do { my $i = 0; 
		  map { $_ => $i++ }
		  qw(c p f i n s t u x v d e g m l) };


sub init {
    my ($self, $context) = @_;

    my @langs = @{$context->config->{'languages'} || []};
    push(@langs, 'Undefined');
    foreach my $l (@langs) {
	eval "require LXRng::Lang::$l";
	die $@ if $@;
	push(@languages, "LXRng::Lang::$l");
    }
}

sub new {
    my ($self, $file) = @_;

    my $pathname = $file->name();

    foreach my $l (@languages) {
	if ($pathname =~ $l->pathexp) {
	    return $l;
	}
    }

    die "No language found for $pathname";
}

1;
