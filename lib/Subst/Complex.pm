package Subst::Complex;

use strict;

sub new {
    my ($self, @args) = @_;

    my (@re, @ac);
    my $l = 1;
    while (@args) {
	my ($r, $a) = splice(@args, 0, 2);
	"" =~ /|$r/;

	push(@ac, [$l+1, $l+1+$#+, $a]);
	$l += 1+$#+;

	push(@re, "($r)");
    }

    return bless {'re' => '((?s:.*?))(?:'.join('|', @re).')',
		  'ac' => \@ac}, $self;
}

sub s {
    my $self;
    my $str;

    if (ref($_[0])) {
	$self = shift;
	$str  = shift;
    }
    else {
	$str  = shift;
	$self = __PACKAGE__->new(@_);
    }

    my @res;
#    $str =~ s{$$self{'re'}}{
#	push(@res, $1) if length($1);
#	my ($a) = grep { defined $-[$$_[0]] } @{$$self{'ac'}};
#	my @g = map { substr($str, $-[$_], $+[$_] - $-[$_]);
#		  } $$a[0]..$$a[1];
#	push(@res, $$a[2]->(@g));
#	'';
#    }ge;
    $str =~ s{$$self{'re'}}{
	push(@res, $1) if length($1);
	my ($a) = grep { defined $-[$$_[0]] } @{$$self{'ac'}};
	my @g = map { substr($str, $-[$_], $+[$_] - $-[$_]);
		  } $$a[0]..$$a[1];
	push(@res, [$$a[2], [@g]]);
	'';
    }ge;

    push(@res, $str) if length($str);
    @res = map {
	ref($_) ? $$_[0]->(@{$$_[1]}) : $_
	} @res;
    
    return @res;
}

1;
