package VisualBT::Engine;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(tick);

sub tick {
    my ($graph, $snapshot, $runtime) = @_;
    $snapshot ||= {}; $runtime ||= { nodes => {}, actionsStarted => 0, trace => [] };
    $runtime->{actionsStarted} = 0; $runtime->{trace} = [];
    my %nodes = map { $_->{id} => $_ } @{$graph->{nodes}};
    my $run; $run = sub {
        my ($id, $depth) = @_;
        die 'depth limit exceeded' if $depth > 20;
        my $n = $nodes{$id} or die "missing node $id";
        my $t = $n->{type}; my $p = $n->{params} || {}; my $children = $n->{children} || [];
        my $state = $runtime->{nodes}{$id} ||= {};
        my $status;
        if ($t eq 'PrioritySelector' || $t eq 'Fallback') {
            my $start = 0;
            if ($t eq 'Fallback' && defined $state->{runningChild}) { for my $i (0..$#$children) { $start = $i if $children->[$i] eq $state->{runningChild} } }
            $status = 'FAILURE';
            for my $i ($start..$#$children) { my $r = $run->($children->[$i], $depth+1); if ($r eq 'ERROR') { $status='ERROR'; last } if ($r eq 'RUNNING' || $r eq 'SUCCESS') { $status=$r; $state->{runningChild}=$children->[$i]; last } }
            delete $state->{runningChild} if $status ne 'RUNNING';
        } elsif ($t eq 'Sequence') {
            # Re-run guards on every visit. This is required after a reactive
            # selector preempts and later re-enters a sequence.
            $status='SUCCESS'; my $begin=0;
            for my $i ($begin..$#$children) { my $r=$run->($children->[$i],$depth+1); if ($r eq 'ERROR' || $r eq 'FAILURE') {$status=$r;last} if ($r eq 'RUNNING') {$status=$r;$state->{index}=$i;last} }
            delete $state->{index} if $status ne 'RUNNING';
        } elsif ($t =~ /\A(?:Inverter|Cooldown|Timeout|Retry|AlwaysSucceed)\z/) {
            my $now=$snapshot->{now}//time; my $child=$children->[0];
            if ($t eq 'Cooldown' && defined($state->{until}) && $now < $state->{until}) {$status='FAILURE'}
            elsif ($t eq 'Timeout' && defined($state->{started}) && ($now-$state->{started})*1000 > $p->{timeoutMs}) {$status='FAILURE';delete $state->{started};$state->{haltRequired}=1}
            elsif ($t eq 'Retry' && defined($state->{retryAt}) && $now < $state->{retryAt}) {$status='RUNNING'}
            else { $state->{started}=$now if $t eq 'Timeout' && !defined $state->{started}; $status=$run->($child,$depth+1);
                if ($t eq 'Inverter') {if ($status eq 'SUCCESS') {$status='FAILURE'} elsif ($status eq 'FAILURE') {$status='SUCCESS'}}
                if ($t eq 'AlwaysSucceed' && $status eq 'FAILURE') {$status='SUCCESS'}
                if ($t eq 'Cooldown' && $status eq 'SUCCESS') {$state->{until}=$now+($p->{durationMs}/1000)}
                if ($t eq 'Retry') {if ($status eq 'FAILURE') {my $attempt=($state->{attempt}//0)+1;if($attempt<$p->{attempts}){$state->{attempt}=$attempt;$state->{retryAt}=$now+($p->{intervalMs}/1000);$status='RUNNING'}else{delete $state->{attempt};delete $state->{retryAt}}}elsif($status eq 'SUCCESS'){delete $state->{attempt};delete $state->{retryAt}}}
                delete $state->{started} if $t eq 'Timeout' && $status ne 'RUNNING';
            }
        } elsif ($t =~ /\A(?:CharacterHp|CharacterSp|WeightPercent|IsSitting|InMap|AggressivesNearby|StatusEffect|InventoryCount|MonsterNearby|CanAccessStorage|HasSkill|ActionIdle)\z/) {
            my %field=(CharacterHp=>'hpPercent',CharacterSp=>'spPercent',WeightPercent=>'weightPercent',IsSitting=>'isSitting',InMap=>'map'); my $key=$field{$t};
            if ($t eq 'AggressivesNearby') {my $m=$snapshot->{aggressives};if(ref($m) ne 'ARRAY'){$status='ERROR'}else{my@typed=grep{!defined($_->{definition})||$_->{definition} eq $p->{definition}||$p->{definition} eq 'either'}@$m;if(grep{!defined($_->{distance})||($p->{requireLOS}&&!defined($_->{hasLOS}))}@typed){$status='ERROR'}else{my@matches=grep{$_->{distance}<=$p->{distance}&&(!$p->{requireLOS}||$_->{hasLOS})}@typed;$status=@matches >= $p->{count}?'SUCCESS':'FAILURE'}}}
            elsif ($t eq 'StatusEffect') {my $s=$snapshot->{statusFlags};$status=ref($s) eq 'HASH'&&exists($s->{$p->{statusId}})?(!!$s->{$p->{statusId}}==!!$p->{active}?'SUCCESS':'FAILURE'):'ERROR'}
            elsif ($t eq 'InventoryCount') {my $i=$snapshot->{inventory};if(ref($i) ne 'HASH'){$status='ERROR'}elsif(!exists($i->{$p->{itemId}})&&!$snapshot->{inventoryComplete}){$status='ERROR'}else{my$v=$i->{$p->{itemId}};my$count=defined($v)?(ref($v) eq 'HASH'?$v->{amount}:$v):0;$status=defined($count)&&_compare($count,$p->{operator},$p->{count})?'SUCCESS':'FAILURE'}}
            elsif ($t eq 'MonsterNearby') {my $m=$snapshot->{monstersVisible};if(ref($m) ne 'ARRAY'){$status='ERROR'}else{my%ids=map{$_=>1}@{$p->{monsterIds}};my@typed=grep{!%ids||$ids{$_->{nameId}//''}}@$m;if(grep{!defined($_->{distance})||($p->{requireLOS}&&!defined($_->{hasLOS}))}@typed){$status='ERROR'}else{my@matches=grep{$_->{distance}<=$p->{distance}&&(!$p->{requireLOS}||$_->{hasLOS})}@typed;$status=@matches >= $p->{count}?'SUCCESS':'FAILURE'}}}
            elsif ($t eq 'CanAccessStorage') {$status=exists($snapshot->{canAccessStorage})?($snapshot->{canAccessStorage}?'SUCCESS':'FAILURE'):'ERROR'}
            elsif ($t eq 'HasSkill') {my $s=$snapshot->{skills};$status=ref($s) eq 'HASH'&&exists($s->{$p->{skillHandle}})?($s->{$p->{skillHandle}}>=$p->{level}?'SUCCESS':'FAILURE'):'ERROR'}
            elsif ($t eq 'ActionIdle') {my $a=$snapshot->{actionIdle};$status=ref($a) eq 'HASH'&&exists($a->{$p->{domain}})?($a->{$p->{domain}}?'SUCCESS':'FAILURE'):'ERROR'}
            elsif (!exists $snapshot->{$key}) {$status='ERROR'}
            elsif ($t eq 'IsSitting') {$status=!!$snapshot->{$key} == !!$p->{expected} ? 'SUCCESS':'FAILURE'}
            elsif ($t eq 'InMap') {$status=$snapshot->{$key} eq $p->{mapName} ? 'SUCCESS':'FAILURE'}
            else {my $v=$snapshot->{$key};$status=_compare($v,$p->{operator},$p->{percent})?'SUCCESS':'FAILURE'}
        } elsif ($t eq 'Wait') {$state->{until}//=($snapshot->{now}//time)+$p->{durationMs}/1000;$status=($snapshot->{now}//time)>=$state->{until}?'SUCCESS':'RUNNING';delete $state->{until} if $status eq 'SUCCESS'}
        elsif ($t eq 'Idle') {$status='RUNNING'}
        else {$status=($graph->{mode}||'shadow') eq 'shadow'?'RUNNING':'ERROR';$state->{reason}='shadow: ação prevista, mas não enviada'}
        $state->{reason}='sensor ou estado necessário indisponível' if $status eq 'ERROR' && !$state->{reason};
        my $entry={nodeId=>$id,status=>$status};$entry->{reason}=$state->{reason} if defined $state->{reason};
        push @{$runtime->{trace}}, $entry;
        return $status;
    };
    my $ok=eval {$run->($graph->{rootId},1)};
    return {status=>$@?'ERROR':$ok, trace=>$runtime->{trace}, runtime=>$runtime, error=>$@||undef};
}
sub _compare {my($a,$op,$b)=@_;return $a<$b if $op eq '<';return $a<=$b if $op eq '<=';return $a>$b if $op eq '>';return $a>=$b if $op eq '>=';return $a==$b}
1;
