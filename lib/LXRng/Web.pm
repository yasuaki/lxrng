package LXRng::Web;

use strict;

use LXRng;
use LXRng::Context;
use LXRng::Lang;
use LXRng::Parse::Simple;
use LXRng::Markup::File;
use LXRng::Markup::Dir;
use Subst::Complex;

use Template;
use IO::Handle;
use Digest::SHA1 qw(sha1_hex);
use CGI::Ajax;
use File::Temp qw(tempdir tempfile);
use POSIX qw(waitpid);

use constant PDF_LINELEN => 95;
use constant PDF_CHARPTS => 6.6;

use vars qw($has_gzip_io);
# eval { require PerlIO::gzip; $has_gzip_io = 1; };

# Return 1 if gzip compression of html is desired.

sub do_compress_response {
    my ($query) = @_;

    my @enc = split(",", $query->http('Accept-Encoding'));
    return $has_gzip_io && grep { $_ eq 'gzip' } @enc;
}


# Progressive output of marked-up file.  If the file in question
# exists in cache, and this is the initial load of an ajax-requested
# file, return only the lines the user wants to see (with a minimum of
# context) as a first approximation.

sub print_markedup_file {
    my ($context, $template, $node) = @_;

    autoflush STDOUT 1;

    unless ($node) {
	print('<div class="error">File not found.</div>');
	return;
    }

    if ($node->isa('LXRng::Repo::Directory')) {
	my $markup = LXRng::Markup::Dir->new('context' => $context,
					     'node' => $node);
	$template->process('content_dir.tt2',
			   {'context' => $context,
			    'dir_listing' => $markup->listing})
	    or die $template->error();
    }
    else {
	# Grmble.  We assume the identifiers to markup are identical
	# from one version to another, but if the same revision of a
	# file exists both in an indexed and un-indexed release, one
	# of them will have its identifiers highlighted and the other
	# not.  So we can't share a cache slot across releases without
	# adding some extra logic here.  Bummer.
	# TODO: Resolve by caching only accesses to releases that are
	# is_indexed.
	my $shaid = sha1_hex(join("\0", $node->name, $node->revision,
				  $context->release));
	my $cfile;
	$cfile = $context->config->{'cache'}.'/'.$shaid
	    if exists $context->config->{'cache'};

	if ($cfile and -e $cfile) {
	    open(my $cache, '<', $cfile);

	    my $focus = $context->param('line') || 0;
	    $focus = 0 if $context->param('full');
	    my $class = $focus ? 'partial' : 'full';
	    my $start = $focus > 5 ? " start=".($focus - 5) : "";
	    print("<pre id=\"file_contents\" class=\"$class\"><ol$start><span>");
	    while (<$cache>) {
		next if $focus and $. < $focus - 5;
		print($_);
		last if $focus and $. > $focus + 70;
	    }
	    print("</span></ol></pre>");
	    close($cache);
	}
	else {
	    my $cache;
	    open($cache, '>', $cfile) if $cfile;
	    my $handle = $node->handle();
	    LXRng::Lang->init($context);
	    my $lang   = LXRng::Lang->new($node);
	    my $parse  = LXRng::Parse::Simple->new($handle, 8,
						   @{$lang->parsespec});
	    my $markup = LXRng::Markup::File->new('context' => $context);
	    my $subst  = $lang->markuphandlers($context, $node, $markup);
    
	    # Possible optimization: store cached file also as .gz,
	    # and pass that on if the client accepts gzip-encoded
	    # data.  Saves us from compressing the cached file each
	    # time it's needed, but requires a bit of fiddling with
	    # perlio and the streams to get right.  Also messes up
	    # partial transfers.
	    print("<pre id=\"file_contents\" class=\"full\"><ol><span>");
	    while (1) {
		my @frags = $markup->markupfile($subst, $parse);
		last unless @frags;
		print(@frags);
		print($cache @frags) if $cache;
	    }
	    print("</span></ol></pre>\n");
	}
    }
}

sub print_tree_list {
    my ($context, $template) = @_;

    my $base = $context->base_url(1);
    $base =~ s,[+]trees/?$,,;
    $template->process('tree_list.tt2',
		       {'context' => $context,
			'base_url' => $base})
		or die $template->error();
}    

sub print_release_list {
    my ($context, $template) = @_;

    $template->process('release_select.tt2',
		       {'context' => $context})
		or die $template->error();
}

sub source {
    my ($context, $template, $query, $template_extra_args) = @_;

    my $pjx = CGI::Ajax->new('pjx_search' => '',
			     'pjx_load_file' => '',
			     'pjx_releases' => '');
    $pjx->js_encode_function('escape');

    if ($context->prefs and $context->prefs->{'navmethod'} eq 'ajax') {
	if ($context->tree ne '') {
	    my $base = $context->base_url(1);
	    my $path = $context->vtree.'/'.$context->path;
	    print($query->redirect($base.'#'.$path));
	}
	else {
	    print($query->header(-type => 'text/html',
				 -charset => 'utf-8'));

	    if ($context->release eq 'trees') {
		print_tree_list($context, $template);
	    }
	    else {
		my $base = $context->base_url(1);
		$base =~ s,/*$,/ajax+*/,;

		$template->process('main.tt2',
				   {'context'    => $context,
				    'base_url'   => $base,
				    'javascript' => $pjx->show_javascript(),
				    'is_ajax' => 1})
		    or die $template->error();
	    }
	}
	return;
    }

    if ($context->tree eq '') {
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8'));
	print_tree_list($context, $template);
	return;
    }


    my $ver = $context->release;
    my $rep = $context->config->{'repository'};
    die "No tree given" unless $rep;

    my $node = $rep->node($context->path, $ver);
    die "Node not found: ".$context->path." ($ver)" unless $node;

    my $gzip = do_compress_response($query);

    my @history = $query->cookie('lxr_history_'.$context->tree);
    if ($node->isa('LXRng::Repo::File')) {
	my $h = $context->path.'+'.$ver;
	@history = ($h, grep { $_ ne $h } @history);
	splice(@history, 15) if @history > 15;
    }

    my $lxr_hist = $query->cookie(-name    => 'lxr_history_'.$context->tree,
				  -values  => \@history,
				  -expires => '+1y');

    print($query->header(-type => 'text/html',
			 -charset => 'utf-8',
			 -cookie => $lxr_hist,
			 $gzip ? (-content_encoding => 'gzip') : ()));

    binmode(\*STDOUT, ":gzip") if $gzip;

    my @rels = @{$context->all_releases()};
    unshift(@rels, $rels[0]);
    while (@rels > 2 and $rels[1] ne $context->release) {
	shift(@rels);
    }

    my $ver_next = @rels > 1 ? $rels[0] : $context->release;
    my $ver_prev = @rels > 2 ? $rels[2] : $context->release;

    my %template_args = (%{$template_extra_args || {}},
			 'context'    => $context,
			 'tree'	      => $context->tree,
			 'node'       => $node,
			 'ver_prev'   => $ver_prev,
			 'ver_next'   => $ver_next,
			 'base_url'   => $context->base_url,
			 'javascript' => $pjx->show_javascript());


    if ($context->prefs and $context->prefs->{'navmethod'} eq 'popup') {
	$template_args{'is_popup'} = 1;
	$template_args{'popup_serial'} = int(rand(1000000));
    }

    if ($node->isa('LXRng::Repo::Directory')) {
	my $markup = LXRng::Markup::Dir->new('context' => $context,
					     'node' => $node);
	$template->process('main.tt2',
			   {%template_args,
			    'dir_listing' => $markup->listing,
			    'is_dir' => 1})
	    or die $template->error();
    }
    else {
	my $html = '';
	$template->process('main.tt2',
			   {%template_args,
			    'file_content' => '<!--FILE_CONTENT-->',
			    'is_dir' => 0},
			   \$html)
	    or die $template->error();
	
	# Template directives in processed template.  Sigh.  TT2 sadly
	# can't do progressive rendering of its templates, so we cheat...
	my ($pre, $post) = split('<!--FILE_CONTENT-->', $html);
	print($pre);
	print_markedup_file($context, $template, $node);
	print($post);
    }

    # TODO: This is potentially useful, in that it resets the stream
    # to uncompressed mode.  However, under Perl 5.8.8+PerlIO::gzip
    # 0.18, this seems to truncate the stream.  Not strictly needed
    # for CGI, reexamine when adapting to mod_perl.
    ## binmode(\*STDOUT, ":pop") if $gzip;
}

#sub ident {
#    my ($self) = @_;

#    my $index = $self->context->config->{'index'};
#    my $view = LXRng::View->new('context' => $self->context);;

#    my $ident  = $self->context->value('ident');
#    my $target = $self->context->value('navtarget');
#    $target ||= 'source';

#    my $rel_id = $index->release_id($self->tree, $self->context->value('v'));
#    my ($symname, $symid, $ident, $refs) =
#        $index->get_identifier_info($ident, $rel_id);

#    $$ident[1] = $LXRng::Lang::deftypes{$$ident[1]};
#    $$ident[5] &&= $LXRng::Lang::deftypes{$$ident[5]};
    
#    return $view->identifier_info($symname, $symid, $ident, $refs, $target);
#}


# Perform various search operations.  Return results as html suitable
# both as a response to an ajax request and inclusion in a more
# general html document.

sub search {
    my ($context, $template, $type, $find) = @_;

    my $ver = $context->release;
    $find ||= $context->param('search');

    my $index = $context->config->{'index'};
    my $rel_id = $index->release_id($context->tree, $ver);
    my %template_args = ('context' => $context);

    $template_args{'navtarget'} = 'target='.$context->param('navtarget')
	if $context->param('navtarget');


    if ($find =~ /\S/) {
	if ($find =~ /^(ident|code):(.*)/) {
	    $type = 'code';
	    $find = $2;
	}
	elsif ($find =~ /^(file|path):(.*)/) {
	    $type = 'file';
	    $find = $2;
	}
	elsif ($find =~ /^(text):(.*)/) {
	    $type = 'text';
	    $find = $2;
	}

	if ($type eq 'file' or $type eq 'search') {
	    my $files = $index->files_by_wildcard($context->tree,
						  $ver, $find);
	    $template_args{'file_res'} = {'query' => $find,
	    				  'files' => $files,}
	}
	if ($type eq 'text' or $type eq 'search') {
	    my $hash  = $context->config->{'search'};
	    my ($total, $res) = $hash->search($rel_id, $find);

	    $template_args{'text_res'} = {'query' => $find,
					  'total' => $total,
					  'files' => $res};
	}
	if ($type eq 'code' or $type eq 'search') {
	    my $result = $index->identifiers_by_name($context->tree, 
						     $ver, $find);
	    my @cooked = (map { $$_[1] = ucfirst($LXRng::Lang::deftypes{$$_[1]});
				$_ }
			  sort { $LXRng::Lang::defweight{$$b[1]} cmp
				     $LXRng::Lang::defweight{$$a[1]} ||
				 $$a[2] cmp $$b[2] ||
				 $$a[3] <=> $$b[3] }
			  @$result);
	    $template_args{'code_res'} = {'query' => $find,
					  'idents' => \@cooked};
	}
	if ($type eq 'ident') {
	    my $usage  = $context->config->{'usage'};
	    my ($symname, $symid, $ident, $refs) =
		$index->get_identifier_info($usage, $find, $rel_id);

	    $$ident[1] = ucfirst($LXRng::Lang::deftypes{$$ident[1]});
	    $$ident[5] &&= $LXRng::Lang::deftypes{$$ident[5]};

	    $template_args{'ident_res'} = {'query' => $symname,
					   'ident' => $ident,
					   'refs' => $refs};
	}
	if ($type eq 'ambig') {
	    my $rep = $context->config->{'repository'};
	    my @args = grep {
		$rep->node($_, $context->release)
	    } split(/\|/, $find);
	    $template_args{'ambig_res'} = {'query' => $find,
					   'files' => \@args,}
	}
    }
    else {
	die "No query string given";
    }
    my $html = '';
    $template_args{'tree'} = $context->tree;
    $template_args{'search_type'} = $type if
	$type =~ /^(search|file|text|code|ident|ambig)$/;
    $template->process('search_result.tt2',
		       \%template_args,
		       \$html)
	or die $template->error();
    return $html;
}


# Display search results for plain and popup navigation methods.
# (Ajax methods call "search" directly.)

sub search_result {
    my ($context, $template, $query, $result) = @_;

    my %template_args = ('context'    => $context,
			 'tree'	      => $context->tree,
			 'search_res' => $result,
			 'base_url'   => $context->base_url);

    if ($context->prefs and $context->prefs->{'navmethod'} eq 'popup') {
	my $gzip = do_compress_response($query);

	print($query->header(-type => 'text/html',
			     -charset => 'utf-8',
			     $gzip ? (-content_encoding => 'gzip') : ()));

	binmode(\*STDOUT, ":gzip") if $gzip;

	$template->process('popup_main.tt2',
			   {%template_args,
			    'is_popup' => 1})
	    or die $template->error();
    }
    else {
	$context->path('');
	source($context, $template, $query, \%template_args);
    }
}


# Callback to perform the ajax-available functions.

sub handle_ajax_request {
    my ($query, $context, $template) = @_;
    my $gzip = do_compress_response($query);
    
    # $query->no_cache(1); FIXME -- not available with CGI.pm.
    print($query->header(-type => 'text/html',
			 -charset => 'utf-8',
			 -cache-control => 'no-store, no-cache, must-revalidate',
			 $gzip ? (-content_encoding => 'gzip') : ()));

    binmode(\*STDOUT, ":gzip") if $gzip;

    if ($context->param('fname') eq 'pjx_load_file') {
	my $rep = $context->config->{'repository'};
	my $node = $rep->node($context->param('file'), $context->release);
	print_markedup_file($context, $template, $node);
	
    }
    elsif ($context->param('fname') eq 'pjx_search') {
	if ($context->param('ajax_lookup') =~
	    /^[+ ](code|ident|file|text|ambig)=(.*)/)
	{
	    print(search($context, $template, $1, $2));
	}
	else {
	    print(search($context, $template, 'search',
			 $context->param('search')));
	}
    }
    elsif ($context->param('fname') eq 'pjx_releases') {
	print_release_list($context, $template);
    }

    # binmode(\*STDOUT, ":pop") if $gzip;    
}


# Stuff user preferences in cookie.

sub handle_preferences {
    my ($query, $context, $template) = @_;

    if ($context->param('resultloc')) {
	my @prefs;
	if ($context->param('resultloc') =~ /^(replace|popup|ajax)$/) {
	    push(@prefs, 'navmethod='.$1);
	}
	my $lxr_prefs = $query->cookie(-name    => 'lxr_prefs',
				       -values  => \@prefs,
				       -expires => '+1y');
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8',
			     -cookie => $lxr_prefs));

	my %template_args;
	if (defined($context->param('return'))) {
	    $template_args{'return'} = $query->param('return');
	}
	else {
	    $template_args{'return'} = $context->base_url(1);
	}
	
	$template->process('prefs_set.tt2',
			   \%template_args)
	    or die $template->error();
    }
    else {
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8'));

	my $nav = 'is_replace';
	$nav = 'is_'.$context->prefs->{'navmethod'} if
	    $context->prefs and $context->prefs->{'navmethod'} ne '';
	    
	my $ret = $context->base_url();
	$ret =~ s,[+]prefs/?,,;
	$ret .= $query->param('return') if $query->param('return');

	$template->process('prefs.tt2',
			   {'return' => $ret,
			    $nav => 1})
	    or die $template->error();
    }
}


# Generate pdf listing of given file.  Much if the following lifted
# from the script "texify".  Proof of concept, code quality could be
# better.

sub generate_pdf {
    my ($query, $context, $template, $path) = @_;

    my $tempdir = tempdir(CLEANUP => 1);

    my %tspecials = (
	'$'	=> '\$',	'*'	=> "\$\\ast\$",
	'&'	=> '\&',	'%'	=> '\%',
	'#'	=> '\#',	'_'	=> '\_',
	'^'	=> '\^{}',	'{'	=> '\{',
	'}'	=> '\}',	'|'	=> "\$|\$",
	'['	=> '{[}',	']'	=> '{]}',
	"'"	=> "{'}",	"\""	=> "\\string\"",
	'~'	=> '\~{}',	'<'	=> "\$<\$",
	'>'	=> "\$>\$",	"\\"	=> "\$\\backslash\$",
	'-'	=> '\dash{}',
# These are latin1-replacements, and interact badly with utf8...
	"\242"	=> '?',		"\244"	=> '?',
	"\245"	=> '?',		"\246"	=> '?',
	"\252"	=> "\$\252\$",	"\254"	=> "\$\254\$",
	"\255"	=> "\\dash{}",	"\260"	=> "\$\260\$",
	"\261"	=> "\$\261\$",	"\262"	=> "\$\262\$",
	"\263"	=> "\$\263\$",	"\265"	=> "\$\265\$",
	"\271"	=> "\$\271\$",	"\272"	=> "\$\272\$",
	"\327"	=> "\$\327\$",	"\367"	=> "\$\367\$",
		     );

    my $tspecials = join('', map { quotemeta($_) } keys(%tspecials));

    my $ver = $context->release;
    my $rep = $context->config->{'repository'};
    my $node = $rep->node($path, $ver);

    die "No such file" unless $node;

    my $handle = $node->handle();
    LXRng::Lang->init($context);
    my $lang   = LXRng::Lang->new($node);
    my $parse  = LXRng::Parse::Simple->new($handle, 8,
					   @{$lang->parsespec});
    my $res    = $lang->reserved();
    my $resre;
    if (%$res) {
	$resre = '(?:(?<=[\s\W])|^)('.
	    join('|', map { my $c = $_; $c =~ s/\#/\\\#/g; quotemeta($c) }
		 sort { length($b) <=> length($a) }
		 keys %$res).')(?=$|[\s\W])';
    }

    my @lines;
    my $row = 1;
    my $col = 0;
    my $line = '\\lxrln{1}';

    while (1) {
	my ($btype, $frag) = $parse->nextfrag;
    
	last unless defined $frag;

	$btype ||= 'code';
	my @parts = split(/(\n)/, $frag);

	while (@parts) {
	    my $part  = shift(@parts);
	    my $align = 0;
	    my $cont  = 0;

	    if ($part eq "\n") {
		push(@lines, $line);

		$col = 0;
		$row++;
		if ($row % 5 == 0) {
		    $line = "\\lxrln{$row}";
		}
		else {
		    $line = '';
		}
		next;
	    }

	    if ($part =~ /^(.*?   +)(.*)/) {
		unshift(@parts, $2);
		$part  = $1;
		$align = 1;
	    }

	    $col += length($part);

	    if ($col > PDF_LINELEN) {
		unshift(@parts, 
			substr($part, PDF_LINELEN - $col, length($part), ''));
		if ($part =~ s/([^\s_,\(\)\{\}\/\=\-\+\*\<\>\[\]\.]+)$//) {
		    if (length($1) < 20) {
			unshift(@parts, $1);
		    }
		    else {
			$part .= $1;
		    }
		}
		$align = 0;
		$cont  = 1;
	    }

	    $part =~ s(([$tspecials\0-\010\013\014\016-\037\200-\240]))
		(exists $tspecials{$1} ? $tspecials{$1} : '?')ge;
	    
	    if ($btype eq 'code') {
		$part =~ s/$resre/\\textbf{$1}/g if $resre;
	    }
	    elsif ($btype eq 'include') {
		$part =~ s/$resre/\\textbf{$1}/ if $resre;
	    }
	    elsif ($btype eq 'comment') {
		$part = '\textit{'.$part.'}';
	    }
	    elsif ($btype eq 'string') {
		$part = '\texttt{'.$part.'}';
	    }

	    # Common fixed-width "ascii-art" characters.
	    $part =~ s/(\$\\ast\$|=)/'\\makebox['.PDF_CHARPTS."pt][c]{$1}"/ge;
	    $line .= $part;
	    if ($align) {
		$line = '\\makebox['.int($col * PDF_CHARPTS).
		    'pt][l]{'.$line.'}';
	    }
	    if ($cont) {
		push(@lines, "$line\\raisebox{-2pt}{\\ArrowBoldRightStrobe}");
		$line = '\\raisebox{-2pt}{\\ArrowBoldDownRight} ';
		$col  = 3;
	    }
	}
    }

    if ($line ne '') {
	push(@lines, $line);
    }
    else {
	$row--;
    }

    if (@lines and $row % 5 != 0) {
	$lines[$#lines] =~ s/^/\\lxrln{$row}/;
    }

    my $pathdesc = $context->tree."/$path ($ver)";
    $pathdesc =~ s/([$tspecials])/$tspecials{$1}/ge;
    
    my ($texh, $texname) = tempfile(DIR => $tempdir, SUFFIX => '.tex');

    $template->process('print_pdf.tt2',
		       {'pathdesc' => $pathdesc,
			'lines' => \@lines},
		       $texh)
	or die $template->error();
    my $pid = fork();
    die $! unless defined($pid);
    if ($pid == 0) {
	close(STDOUT);
	open(STDOUT, "> $texname.output");
	close(STDERR);
	open(STDERR, ">&STDOUT");
	chdir($tempdir);
	exec("pdflatex", "$texname");
	kill(9, $$);
    }
    waitpid($pid, 0);
    my $pdfname = $texname;
    $pdfname =~ s/[.]tex$/.pdf/;
    if (-e $pdfname) {
	open(my $pdfh, "< $pdfname") or die $!;

	print($query->header(-type => 'application/pdf',
			     -content_disposition =>
			     "inline; filename=$path.pdf"));
	my $buf = '';
	while (sysread($pdfh, $buf, 65536) > 0) {
	    print($buf);
	}
	close($pdfh);
    }
    elsif (-e "$texname.output") {
	open(my $errh, "< $texname.output") or die $!;
	my @err = <$errh>;
	close($errh);
	@err = splice(@err, -15) if @err > 15;
	die "PDF generation failed: ".join("\n", @err);
    }
    else {
	die "PDF generation failed";
    }
}


sub handle {
    my ($self, $query) = @_;

    my $context  = LXRng::Context->new('query' => $query);
    my $template = Template->new({'INCLUDE_PATH' => $LXRng::ROOT.'/tmpl/'});

    if ($context->param('fname')) {
	handle_ajax_request($query, $context, $template);
    }
    else {	
	if ($context->path =~ /^[+ ]prefs$/) {
	    handle_preferences($query, $context, $template);
	}
	elsif ($context->path =~ /^[+ ]print=(.*)/) {
	    generate_pdf($query, $context, $template, $1);
	}
	else {
	    if ($context->path =~ 
		/^[+ ](search|code|ident|file|text|ambig)(?:=(.*)|)/)
	    {
		search_result($context, $template, $query,
			      search($context, $template, $1, $2));
		$context->path('');
	    }
	    else {
		source($context, $template, $query);
	    }
	}
    }
}

1;