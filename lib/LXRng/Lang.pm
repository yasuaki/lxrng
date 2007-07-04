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
		  qw(c f i n s t u p x v d e g m l) };


sub import {
    my ($self, @langs) = @_;

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
