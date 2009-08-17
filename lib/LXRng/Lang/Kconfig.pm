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

package LXRng::Lang::Kconfig;

use strict;
use Subst::Complex;

use base qw(LXRng::Lang::Generic);


sub doindex {
    return 1;
}

sub ctagslangname {
    return undef;
}

sub pathexp {
    return qr/Kconfig$/;
}

my $_identifier_re = qr(
			(?m:^|(?<=[^A-Z0-9_\#]))	# Non-symbol chars.
			(_*[A-Z][A-Z0-9_]*)		# The symbol.
			\b
			)x;

sub identifier_re {
    return $_identifier_re;
}

my $_reserved = { map { $_ => 1 }
		  qw(menu source endmenu config bool if default help
		     tristate depends on y n m)};

sub reserved {
    return $_reserved;
}

sub parsespec {
    return ['atom',	'\\\\.',	undef,
	    'comment',	'#',		"\$",
	    'string',	'"(?:[^\\\\]*\\\\.)*[^\\\\]*"', undef,
	    'string',	"'(?:[^\\\\]*\\\\.)*[^\\\\]*'", undef,
	    'help',     'help', 	"^(?=[^ \t\n])",
	    'include',	'^source\s+"',	'"'];
}

sub mangle_sym {
    return $_[1] =~ /^[A-Z0-9_]+$/ ? 'CONFIG_'.$_[1] : $_[1];
}

sub markuphandlers {
    my ($self, $context, $node, $markup) = @_;

    my $index = $context->config->{'index'};
    my %subst;

    my $format_newline = $markup->make_format_newline($node);
    $subst{'comment'} = new Subst::Complex
	qr/\n/     => $format_newline,
	qr/[^\n]+/ => sub { $markup->format_comment(@_) };
	
    $subst{'help'} = new Subst::Complex
	qr/\n/        => $format_newline,
	qr/^[ \t]*help[ \t]*/ => sub { $markup->format_code($self, @_) },
	qr/[^\n\"\']+/ => sub { $markup->format_string(@_) };

    $subst{'string'} = new Subst::Complex
	qr/\n/     => $format_newline,
	qr/[^\n]+/ => sub { $markup->format_string(@_) };

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
	qr/[^\n]*/ => sub { $markup->format_code($self, @_) };

    $subst{'start'} = new Subst::Complex
	qr/^/	   => $format_newline;
    
    return \%subst;
}

sub resolve_include {
    my ($self, $context, $node, $frag) = @_;

    return ();
}

sub index_file {
    my ($self, $context, $file, $add_ident) = @_;

    my $handle = $file->handle();
    my $parse  = LXRng::Parse::Simple->new($handle, 8,
					   @{$self->parsespec});

    my $line = 1;
    while (1) {
	my ($btype, $frag) = $parse->nextfrag;

	return 1 unless defined $frag;

	$btype ||= 'code';
	if ($btype eq 'code') {
	    while ($frag =~ s/\A(.*)^config (\w+)//) {
		my ($pref, $sym) = ($1, $2);
		$line += $pref =~ tr/\n/\n/;
		$add_ident->($self->mangle_sym($sym),
			     {'kind' => 'd',
			      'line' => $line});
	    }
	}
	$line += $frag =~ tr/\n/\n/;
    }
}


1;

