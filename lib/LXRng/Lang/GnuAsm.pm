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

package LXRng::Lang::GnuAsm;

use strict;
use Subst::Complex;

use base qw(LXRng::Lang::Generic);


sub doindex {
    return 1;
}

sub ctagslangname {
    return 'asm';
}

sub ctagsopts {
    return ();
}

sub pathexp {
    return qr/\.[sS]$/;
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
		    (qw(aaa aad aam aas adc bound bsf bsr bswap btc
		       btr call cbw cwde cdqe cwd cdq cqo clc cld
		       clflush cmc cmps cmpsb cmpsw cmpsd cmpsq
		       cmpxchg cmpxchg8b cmpxchg16b cpuid daa das
		       enter ins insb insw insd int into jcxz jecxz
		       jrcxz jmp lahf lds les lfs lgs lss leave lfence
		       lock lods lodsb lodsw lodsd lodsq loop loope
		       loopne loopnz loopz mfence movd movmskpd
		       movmskps movnti movs movsb movsw movsd movsq
		       movsx movsxd movzx nop outs outsb outsw outsd
		       pause popa popad prefetch prefetchw pusha
		       pushad pushfd pushfq ret sahf sbb scas scasb
		       scasw scasd scasq sfence stc std stos stosb
		       stosw stosd stosq xadd xchg xlat xlatb arpl
		       clgi cli clts hlt int invd invlpg invlpga iret
		       iretd iretq lar lgdt lidt lldt lmsw lretq lsl
		       ltr rep rdmsr rdpmc rdtsc rdtscp rsm sgdt sidt
		       skinit sldt smsw sti stgi str swapgs syscall
		       sysenter sysexit sysret ud2 verr verw vmload
		       vmmcall vmrun vmsave wbinvd wrmsr),

		     (map { $_, $_.'b', $_.'w', $_.'l', $_.'q' }
		      qw(add and mov bt bts cmp dec div idiv imul inc
			 in lea mul neg not or out pop popf push pushf
			 rcl rcr rol ror sal shl sar shl shr sub test
			 xor)),

		     (map { 'cmov'.$_, 'j'.$_, 'set'.$_ }
		      qw(o no b c nae nb nc ae z e nz ne be na nbe a s
			 ns p pe np po l nge nl ge le ng nle g))
		     )};
		     

sub reserved {
    return $_reserved;
}

sub parsespec {
    return ['atom',	'\\\\.',	undef,
	    'atom',	'%[a-z][a-z0-9]+', undef, # Registers
	    'atom',	'[.][a-z0-9]+', undef, # Directives
	    'comment',	'/\*',		'\*/',
	    'comment',	'//',		"\$",
	    'string',	'"(?:[^\\\\]*\\\\.)*[^\\\\]*"', undef,
	    'string',	"'(?:[^\\\\]*\\\\.)*[^\\\\]*'", undef,
	    'atom',	'#\s*(?:ifn?def|define|else|endif|undef)', undef,
	    'include',	'#\s*include\s+"',	'"',
	    'include',	'#\s*include\s+<',	'>',
	    'comment',	'#',		"\$"];
}

sub markuphandlers {
    my ($self, $context, $node, $markup) = @_;

    my $index = $context->config->{'index'};
    my %subst;

    my $format_newline = $markup->make_format_newline($node);
    $subst{'comment'} = new Subst::Complex
	qr/\n/     => $format_newline,
	qr/[^\n]+/ => sub { $markup->format_comment(@_) };
	
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
