package LXRng::Lang::Generic;

use strict;

sub expand_include {
    my ($self, $context, $node, $include) = @_;

    return () unless $context->config->{'include_maps'};

    my $file = $node->name();
    foreach my $map (@{$context->config->{'include_maps'}}) {
	my @key = $file =~ /($$map[0])/ or next;
	my @val = $include =~ /($$map[1])/ or next;
	shift(@key);
	shift(@val);
	my @paths = $$map[2]->(@key, @val);
	
	return map { /([^\/].*)/ ? $1 : $_ } @paths;
    }

    return ();
}

1;
