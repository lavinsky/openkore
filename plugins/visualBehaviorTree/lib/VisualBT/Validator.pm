package VisualBT::Validator;
use strict;
use warnings;
use Exporter 'import';
use Scalar::Util qw(blessed);
our @EXPORT_OK = qw(validate_graph);

sub validate_graph {
    my ($graph, $catalog) = @_;
    my @errors;
    return (0, ['graph must be an object']) unless ref($graph) eq 'HASH';
    my %allowed_graph=map {$_=>1} qw(schemaVersion profileId name description mode managedDomains rootId nodes layout metadata);
    push @errors, "unexpected graph field: $_" for grep {!$allowed_graph{$_}} keys %$graph;
    for my $key (qw(schemaVersion profileId name description mode managedDomains rootId nodes)) {
        push @errors, "missing field: $key" unless exists $graph->{$key};
    }
    for my $key (qw(profileId name description rootId)) { push @errors, "$key must be a string" if exists($graph->{$key}) && (!defined($graph->{$key}) || ref($graph->{$key})) }
    push @errors, 'name length must be 1..120' if defined($graph->{name}) && !ref($graph->{name}) && (length($graph->{name})<1 || length($graph->{name})>120);
    push @errors, 'description exceeds 2000 characters' if defined($graph->{description}) && !ref($graph->{description}) && length($graph->{description})>2000;
    push @errors, 'profileId is invalid' if defined($graph->{profileId}) && !ref($graph->{profileId}) && $graph->{profileId}!~/\A[a-zA-Z0-9_-]{1,64}\z/;
    push @errors, 'rootId is invalid' if defined($graph->{rootId}) && !ref($graph->{rootId}) && $graph->{rootId}!~/\A[a-zA-Z0-9_-]{1,64}\z/;
    push @errors, 'unsupported schemaVersion' unless ($graph->{schemaVersion} // '') eq '1';
    push @errors, 'mode must be shadow, assist, or managed' unless ($graph->{mode} // '') =~ /\A(?:shadow|assist|managed)\z/;
    push @errors, 'managedDomains must be an array' unless ref($graph->{managedDomains}) eq 'ARRAY';
    my %domain_allowed=map {$_=>1} qw(combat movement rest self_skills items storage teleport_strategy);
    push @errors, "unknown managed domain: $_" for ref($graph->{managedDomains}) eq 'ARRAY' ? grep {!$domain_allowed{$_}} @{$graph->{managedDomains}} : ();
    push @errors, 'layout must be an object' if exists($graph->{layout}) && ref($graph->{layout}) ne 'HASH';
    push @errors, 'metadata must be an object' if exists($graph->{metadata}) && ref($graph->{metadata}) ne 'HASH';
    push @errors, 'managedDomains is only valid in managed mode' if ref($graph->{managedDomains}) eq 'ARRAY' && $graph->{mode} ne 'managed' && @{$graph->{managedDomains}};
    return (0, \@errors) if @errors;
    push @errors, 'nodes must be an array' unless ref($graph->{nodes}) eq 'ARRAY';
    return (0, \@errors) if @errors;
    push @errors, 'document exceeds 256 KiB' if length($graph->{_raw} // '') > 262144;
    my $nodes = $graph->{nodes};
    push @errors, 'node count must be 1..200' if !@$nodes || @$nodes > 200;
    my %types = map { $_->{typeId} => $_ } @{$catalog->{nodes} || []};
    my (%by_id, %parents);
    for my $n (@$nodes) {
        if (ref($n) ne 'HASH') { push @errors, 'node must be an object'; next }
        my $id = $n->{id};
        push @errors, "node has unexpected field: $_" for grep {$_ ne 'id' && $_ ne 'type' && $_ ne 'params' && $_ ne 'children'} keys %$n;
        if (!defined($id) || ref($id) || $id !~ /\A[a-zA-Z0-9_-]{1,64}\z/) { push @errors, 'node id is invalid'; next }
        push @errors, "duplicate node id: $id" if exists $by_id{$id};
        $by_id{$id} = $n;
        push @errors, "node $id type is unknown" unless exists $types{$n->{type}};
        push @errors, "node $id params must be an object" unless ref($n->{params}) eq 'HASH';
        push @errors, "node $id children must be an array" unless ref($n->{children}) eq 'ARRAY';
        next unless exists $types{$n->{type}} && ref($n->{children}) eq 'ARRAY' && ref($n->{params}) eq 'HASH';
        my $spec = $types{$n->{type}};
        my ($min, $max) = @{$spec->{ports}}{qw(minChildren maxChildren)};
        push @errors, "node $id child count outside limits" if @{$n->{children}} < $min || @{$n->{children}} > $max;
        for my $k (keys %{$n->{params}}) { push @errors, "node $id has unexpected parameter $k" unless exists $spec->{inputSchema}{$k} }
        for my $k (keys %{$spec->{inputSchema}}) { push @errors, "node $id missing parameter $k" unless exists $n->{params}{$k} }
        for my $k (keys %{$spec->{inputSchema}}) {
            next unless exists $n->{params}{$k};
            my $rule = $spec->{inputSchema}{$k}; my $v = $n->{params}{$k};
            if ($rule->{type} eq 'enum') { push @errors, "node $id parameter $k invalid" unless !ref($v) && grep { $_ eq $v } @{$rule->{values}} }
            elsif ($rule->{type} eq 'string') { push @errors, "node $id parameter $k invalid" unless !ref($v) && length($v) >= ($rule->{minLength}//0) && length($v) <= ($rule->{maxLength}//9999) }
            elsif ($rule->{type} eq 'boolean') { push @errors, "node $id parameter $k must be boolean" unless (!ref($v) && ($v eq '0' || $v eq '1')) || (blessed($v) && blessed($v) =~ /Boolean\z/) }
            elsif ($rule->{type} =~ /\A(?:integer|number)\z/) { push @errors, "node $id parameter $k out of range" unless defined($v) && !ref($v) && $v =~ /\A-?\d+(?:\.\d+)?\z/ && $v >= ($rule->{minimum}//-1e99) && $v <= ($rule->{maximum}//1e99) && ($rule->{type} ne 'integer' || int($v) == $v) }
            elsif ($rule->{type} eq 'array') { push @errors, "node $id parameter $k invalid" unless ref($v) eq 'ARRAY' && @$v >= ($rule->{minItems}//0) && @$v <= ($rule->{maxItems}//9999) && !grep { ref($_) || $_ !~ /\A[1-9]\d*\z/ } @$v }
        }
        for my $child (@{$n->{children}}) {
            if (!defined($child) || ref($child)) { push @errors, "node $id child id invalid"; next }
            $parents{$child}++;
        }
    }
    my $root = $graph->{rootId};
    push @errors, 'rootId does not exist' unless defined($root) && exists $by_id{$root};
    if (defined $root && exists $by_id{$root}) {
        push @errors, 'root has a parent' if $parents{$root};
        for my $id (keys %by_id) { push @errors, "node $id has multiple parents" if $id ne $root && ($parents{$id} // 0) > 1; push @errors, "node $id is orphaned" if $id ne $root && !$parents{$id} }
        my (%visiting, %seen);
        my $walk; $walk = sub {
            my ($id, $depth) = @_;
            if ($depth > 20) { push @errors, 'tree depth exceeds 20'; return }
            if ($visiting{$id}) { push @errors, "cycle at node $id"; return }
            return if $seen{$id}++;
            $visiting{$id} = 1;
            my $n = $by_id{$id};
            $walk->($_, $depth + 1) for ref($n) eq 'HASH' && ref($n->{children}) eq 'ARRAY' ? @{$n->{children}} : ();
            delete $visiting{$id};
        };
        $walk->($root, 1);
        push @errors, 'tree contains unreachable nodes' if keys(%seen) != keys(%by_id);
    }
    if ($graph->{mode} eq 'managed') {
        my %domains = map { $_ => 1 } @{$graph->{managedDomains}};
        for my $n (@$nodes) { my $s = $types{$n->{type} || ''}; next unless $s && $s->{domain}; push @errors, "node $n->{id} domain $s->{domain} is not managed" unless $domains{$s->{domain}} }
    }
    if ($graph->{mode} ne 'shadow') {
        for my $n (@$nodes) { my $s = $types{$n->{type} || ''}; next unless $s; push @errors, "node $n->{id} requires unsupported runtime capability: $_" for @{$s->{requiredCapabilities} || []} }
    }
    return (@errors ? 0 : 1, \@errors);
}
1;
