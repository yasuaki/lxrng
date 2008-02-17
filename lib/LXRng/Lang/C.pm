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

package LXRng::Lang::C;

use strict;
use Subst::Complex;

use base qw(LXRng::Lang::Generic);


sub doindex {
    return 1;
}

sub ctagslangname {
    return 'c';
}

sub ctagsopts {
    return ('--c-types=+lpx');
}

sub pathexp {
    return qr/\.[ch]$/;
}

my $_identifier_re = qr(
			(?m:^|(?<=[^a-zA-Z0-9_\#]))	# Non-symbol chars.
			(_*[a-zA-Z][a-zA-Z0-9_]*)	# The symbol.
			\b
			)x;

sub identifier_re {
    return $_identifier_re;
}

my $_reserved ||= { map { $_ => 1 }
		    qw(asm auto break case char const continue default
		       do double else enum extern float for fortran
		       goto if int long register return short signed
		       sizeof static struct switch typedef union
		       unsigned void volatile while #define #else
		       #endif #if #ifdef #ifndef #include #undef)};

sub reserved {
    return $_reserved;
}

sub parsespec {
    return ['atom',	'\\\\.',	undef,
	    'comment',	'/\*',		'\*/',
	    'comment',	'//',		"\$",
	    'string',	'"',		'"',
	    'string',	"'",		"'",
	    'include',	'#\s*include\s+"',	'"',
	    'include',	'#\s*include\s+<',	'>'];
}

sub typemap {
    return {
	'c' => 'class',
	'd' => 'macro (un)definition',
	'e' => 'enumerator',
	'f' => 'function definition',
	'g' => 'enumeration name',
	'm' => 'class, struct, or union member',
	'n' => 'namespace',
	'p' => 'function prototype or declaration',
	's' => 'structure name',
	't' => 'typedef',
	'u' => 'union name',
	'v' => 'variable definition',
	'x' => 'extern or forward variable declaration',
	'i' => 'interface'};
}

sub markuphandlers {
    my ($self, $context, $node, $markup) = @_;

    my $index = $context->config->{'index'};
    my $idre = $self->identifier_re();
    my $res  = $self->reserved();

    my %subst;

    my $format_newline = $markup->make_format_newline($node);
    $subst{'comment'} = new Subst::Complex
	qr/\n/     => $format_newline,
	qr/[^\n]+/ => sub { $markup->format_comment(@_) };
	
    $subst{'string'} = new Subst::Complex
	qr/\n/        => $format_newline,
	qr/[^\n\"\']+/ => sub { $markup->format_string(@_) };

    $subst{'include'} = new Subst::Complex
	qr/\n/ => $format_newline,
	qr/(include\s*\")(.*?)(\")/ => sub {
	    $markup->format_include([$self->resolve_include($context, $node, @_)],
				    @_) },
				  
	qr/(include\s*\<)(.*?)(\>)/ => sub {
	    $markup->format_include([$self->resolve_include($context, $node, @_)],
				    @_) };
	
    $subst{'code'} = new Subst::Complex
	qr/\n/	   => $format_newline,
	qr/[^\n]*/ => sub { $markup->format_code($idre, $res, @_) };

    $subst{'start'} = new Subst::Complex
	qr/^/	   => $format_newline;
    
    return \%subst;
}

sub resolve_include {
    my ($self, $context, $node, $frag) = @_;

    if ($frag =~ /include\s+<(.*?)>/) {
	return $self->expand_include($context, $node, $1);
    }
    elsif ($frag =~ /include\s+\"(.*?)\"/) {
	my $incl = $1;
	my $bare = $1;
	my $name = $node->name();
	if ($name =~ /(.*\/)/) {
	    $incl = $1.$incl;
	    1 while $incl =~ s,/[^/]+/../,/,;
	    
	    my $file = $context->config->{'repository'}->node($incl, $context->release);
	    return $incl if $file;
	    return $self->expand_include($context, $node, $bare);
	}
    }

    return ();
}

1;
