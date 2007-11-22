package LXRng::Markup::File;

use strict;
use HTML::Entities;

sub new {
    my ($class, %args) = @_;

    return bless(\%args, $class);
}

sub context {
    my ($self) = @_;
    return $$self{'context'};
}

sub safe_html {
    my ($str) = @_;
    return encode_entities($str, '^\n\r\t !\#\$\(-;=?-~\200-\377');
}

sub make_format_newline {
    my ($self, $node) = @_;
    my $line = 0;
    my $tree = $self->context->vtree();
    my $name = $node->name;

    sub {
	my ($nl) = @_;
	$line++;
	$nl = safe_html($nl);

	return qq{</span>$nl<li>}.
	    qq{<a href="$name#L$line" class="line"><span></span></a>}.
	    qq{<a id="L$line" name="L$line"></a><span class="line">};
    }
}

sub format_comment {
    my ($self, $com) = @_;

    $com = safe_html($com);
    return qq{<span class="comment">$com</span>};
}
	

sub format_string {
    my ($self, $str) = @_;

    $str = safe_html($str);
    return qq{<span class="string">$str</span>}
}

sub format_include {
    my ($self, $paths, $all, $pre, $inc, $suf) = @_;
    
    my $tree = $self->context->vtree();
    if (@$paths > 1) {
	$pre = safe_html($pre);
	$inc = safe_html($inc);
	$suf = safe_html($suf);
	my $alts = join("|", map { $_ } @$paths);
	return qq{$pre<a href="+ambig=$alts" class="falt">$inc</a>$suf};
    }
    elsif (@$paths > 0) {
	$pre = safe_html($pre);
	$inc = safe_html($inc);
	$suf = safe_html($suf);
	return qq{$pre<a href="$$paths[0]" class="fref">$inc</a>$suf};
    }
    else {
	return safe_html($all);
    }
}

sub format_code {
    my ($self, $idre, $syms, $frag) = @_;

    my $tree = $self->context->vtree();
    my $path = $self->context->path();
    Subst::Complex::s($frag,
		      $idre => sub {
			  my $sym = $_[1];
			  if (exists($$syms{$sym})) {
			      $sym = safe_html($sym);
			      return qq{<a href="+code=$sym" class="sref">$sym</a>}
			  }
			  else {
			      return safe_html($sym);
			  }
		      },
		      qr/(.*?)/ => sub { return safe_html($_[0]) },
		      );
}

sub format_raw {
    my ($self, $str) = @_;

    $str = safe_html($str);
    $str =~ s((http://[^/\"]+(/[^\s\"]*|)[^.\,\)\>\"]))
	(<a href="$1">$1</a>)g;
    return $str;
}

sub markupfile {
    my ($self, $subst, $parse) = @_;

    my ($btype, $frag) = $parse->nextfrag;
    
    return () unless defined $frag;

    $btype ||= 'code';
    if ($btype and exists $$subst{$btype}) { 
	return $$subst{$btype}->s($frag);
    }
    else {
	return $frag;
    }
}

1;
