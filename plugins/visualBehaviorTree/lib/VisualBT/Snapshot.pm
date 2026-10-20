package VisualBT::Snapshot;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(build_snapshot);

# Inputs are injected readers so this module can be tested without OpenKore.
# Every sensor carries readiness; unavailable data stays unavailable, never false.
sub build_snapshot {
    my ($readers, $now) = @_;
    $readers ||= {};
    my %out=(now=>$now);
    my %fields=(hpPercent=>[qw(hp_percent)],spPercent=>[qw(sp_percent)],weightPercent=>[qw(weight_percent)],map=>[qw(map)],position=>[qw(position)],isSitting=>[qw(is_sitting)],isDead=>[qw(is_dead)],inventory=>[qw(inventory)],inventoryComplete=>[qw(inventory_complete)],statusFlags=>[qw(status_flags)],skills=>[qw(skills)],aiState=>[qw(ai_state)],aiAction=>[qw(ai_action)],actionIdle=>[qw(action_idle)],monstersVisible=>[qw(monsters_visible)],aggressives=>[qw(aggressives)],canAccessStorage=>[qw(can_access_storage)],connected=>[qw(connected)]);
    for my $field (keys %fields) {
        my $reader=$readers->{$field};
        next unless ref($reader) eq 'CODE';
        my ($value,$ready)=eval {$reader->()};
        next if $@ || !$ready || !defined $value;
        if ($field eq 'position') {
            next unless ref($value) eq 'HASH' && defined($value->{x}) && defined($value->{y});
            $out{$field}={x=>0+$value->{x},y=>0+$value->{y}};
        } elsif ($field eq 'map') { $out{$field}="$value" }
        elsif ($field eq 'inventory') {
            next unless ref($value) eq 'HASH'; my %items;
            for my $item (keys %$value) {next unless $item =~ /^\d+$/;my $v=$value->{$item};my $amount=ref($v) eq 'HASH'?$v->{amount}:$v;next unless defined($amount)&&$amount =~ /^\d+$/;$items{$item}={amount=>0+$amount}}
            $out{$field}=\%items;
        } elsif ($field eq 'statusFlags' || $field eq 'skills' || $field eq 'actionIdle') {
            next unless ref($value) eq 'HASH';my %safe;for my $key(keys %$value){next unless $key =~ /^[A-Za-z0-9_.:-]{1,80}$/;my $v=$value->{$key};next if ref($v);$safe{$key}=$v?1:0 if $field eq 'statusFlags' || $field eq 'actionIdle';$safe{$key}=0+$v if $field eq 'skills' && defined($v)&&$v =~ /^\d+$/}$out{$field}=\%safe;
        } elsif ($field eq 'monstersVisible' || $field eq 'aggressives') {
            next unless ref($value) eq 'ARRAY';my @safe;
            for my $m (@$value) {next unless ref($m) eq 'HASH';my %row;for my $k(qw(nameId distance hasLOS definition attackingMe)){next unless exists $m->{$k};my $v=$m->{$k};next if ref($v);next unless defined $v;if($k eq 'nameId'){next unless $v =~ /^\d+$/;$row{$k}=0+$v}elsif($k eq 'distance'){next unless $v =~ /^\d+(?:\.\d+)?$/;$row{$k}=0+$v}elsif($k eq 'hasLOS'||$k eq 'attackingMe'){$row{$k}=$v?1:0}elsif($k eq 'definition'){next unless $v =~ /^(?:either|attackingMe|monsterTypeAggressive)$/;$row{$k}=$v}}
                # Actor IDs, names, raw objects and packet fields never leave the adapter.
                push @safe,\%row if exists($row{distance}) || $field eq 'aggressives';
            }$out{$field}=\@safe;
        } elsif ($field eq 'hpPercent'||$field eq 'spPercent'||$field eq 'weightPercent') {next unless $value =~ /^\d+(?:\.\d+)?$/;$out{$field}=0+$value}
        elsif ($field eq 'aiState' || $field eq 'aiAction') {next unless $value =~ /^[A-Za-z_]{1,40}$/;$out{$field}=$value}
        else {$out{$field}=$value?1:0}
    }
    return \%out;
}
1;
