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
