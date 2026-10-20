package VisualBT::OpenKoreReader;
use strict;
use warnings;
use Exporter 'import';
use VisualBT::Snapshot qw(build_snapshot);
our @EXPORT_OK = qw(build_openkore_snapshot readers_for);

# Native globals are injected so snapshots can be exercised without a client.
sub readers_for {
    my (%o) = @_;
    my ($char,$field,$ai,$config) = @o{qw(char field ai config)};
    my %r;
    $r{connected}=sub { return ($o{connected}?1:0, defined $o{connected}) };
    for my $pair ([hpPercent=>'hp_percent'],[spPercent=>'sp_percent'],[weightPercent=>'weight_percent']) {
        my ($key,$method)=@$pair;
        $r{$key}=sub { return (undef,0) unless $char && $char->can($method); my $v=eval{$char->$method()}; return ($v,!$@ && defined($v) && $v =~ /^\d+(?:\.\d+)?$/ && $v <= 100) };
    }
    $r{map}=sub { return (undef,0) unless $field && $field->can('baseName'); my $v=eval{$field->baseName}; return ($v,!$@ && defined($v) && $v =~ /^[A-Za-z0-9_.-]{1,32}$/) };
    $r{position}=sub { return (undef,0) unless $char && $char->can('position'); my $p=eval{$char->position}; return (undef,0) if $@ || ref($p) ne 'HASH' || !defined($p->{x}) || !defined($p->{y}); return ({x=>$p->{x},y=>$p->{y}},1) };
    $r{isSitting}=sub { return (undef,0) unless $char && exists $char->{sitting}; return ($char->{sitting}?1:0,1) };
    $r{isDead}=sub { return (undef,0) unless $char && exists $char->{dead}; return ($char->{dead}?1:0,1) };
    $r{inventory}=sub { return (undef,0) unless $char && $char->can('inventory'); my $inv=eval{$char->inventory}; return (undef,0) if $@ || !$inv || !$inv->can('isReady') || !$inv->isReady; my %items; for my $it (@$inv) {next unless $it;my $id=$it->{nameID};my $amount=$it->{amount};$items{$id}+=$amount if defined($id)&&$id=~/^\d+$/&&defined($amount)&&$amount=~/^\d+$/} return (\%items,1) };
    $r{inventoryComplete}=sub { return ($char && $char->can('inventory') && eval{$char->inventory->isReady}?1:0,1) };
    $r{statusFlags}=sub { return (undef,0) unless $char && ref($char->{statuses}) eq 'HASH'; my %v;for my $key(keys %{$char->{statuses}}){$v{$key}=$char->can('statusActive')&&eval{$char->statusActive($key)}?1:0}return (\%v,1) };
    $r{skills}=sub { return (undef,0) unless $char && ref($char->{skills}) eq 'HASH'; my %v;for my $k(keys %{$char->{skills}}){my $v=$char->{skills}{$k};$v=$v->{lv} if ref$v eq 'HASH';$v=0 unless defined$v;$v{$k}=$v} return (\%v,1) };
    $r{aiState}=sub {return (undef,0) unless $ai && $ai->can('state');my $v=eval{$ai->state};return (undef,0) if $@ || !defined$v;return ($v==2?'AUTO':$v==1?'MANUAL':'OFF',1)};
    $r{aiAction}=sub {return (undef,0) unless $ai && $ai->can('action');my $v=eval{$ai->action};return ($v,!$@&&defined$v)};
    $r{actionIdle}=sub {return ({},0)};
    $r{monstersVisible}=sub {return (undef,0) unless ref($o{monsters}) eq 'ARRAY';my @v;for my $m(@{$o{monsters}}){next unless ref$m eq 'HASH';push @v,{nameId=>$m->{nameID},distance=>$m->{distance},hasLOS=>$m->{hasLOS}} if defined$m->{distance}}return (\@v,1)};
    $r{aggressives}=sub {return (undef,0) unless ref($o{aggressives}) eq 'ARRAY';my @v;for my $m(@{$o{aggressives}}){next unless ref$m eq 'HASH';push @v,{definition=>$m->{definition},distance=>$m->{distance},hasLOS=>$m->{hasLOS},attackingMe=>$m->{attackingMe}} if defined$m->{distance}}return (\@v,1)};
    $r{canAccessStorage}=sub {return (undef,0) unless $config && exists$config->{storageAuto}; return ($config->{storageAuto} && ($config->{storageAuto_npc} || $config->{storageAuto_useItem} || $config->{storageAuto_useChatCommand}) ? 1:0,1)};
    $r{capabilities}=sub {return ({requiredCapabilities=>[]},1)};
    return \%r;
}
sub build_openkore_snapshot { my ($now,%o)=@_;return build_snapshot(readers_for(%o),$now) }
1;
