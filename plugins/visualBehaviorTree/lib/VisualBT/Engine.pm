package VisualBT::Engine;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(tick halt);

my %ACTION = map { $_ => 1 } qw(Stand Sit MoveOneTile MoveTo TeleportRandom ReturnToSavePoint AttackTarget UseSkill UseItem StoreAtKafra RestUntil Wait);

sub tick {
    my ($graph, $snapshot, $runtime, $adapter) = @_;
    $snapshot ||= {};
    $runtime ||= { nodes => {} };
    $runtime->{nodes} ||= {};
    $runtime->{now} = $snapshot->{now}//time;
    $runtime->{actionsStarted} = 0;
    $runtime->{trace} = [];
    $runtime->{dispatchBlocked} = 0;
    _reconcile_halts($runtime,$snapshot,$adapter);
    my %nodes = map { $_->{id} => $_ } @{$graph->{nodes} || []};
    my $run;
    $run = sub {
        my ($id, $depth) = @_;
        die 'depth limit exceeded' if $depth > 20;
        my $n = $nodes{$id} or die "missing node $id";
        my ($t, $p, $children) = ($n->{type}, $n->{params} || {}, $n->{children} || []);
        my $s = $runtime->{nodes}{$id} ||= {};
        my $status;
        if ($t eq 'PrioritySelector' || $t eq 'Fallback') {
            my $start = 0;
            if ($t eq 'Fallback' && defined $s->{runningChild}) {
                for my $i (0..$#$children) { $start=$i if $children->[$i] eq $s->{runningChild} }
            }
            my $previous = $s->{runningChild};
            $status='FAILURE';
            for my $i ($start..$#$children) {
                my $child=$children->[$i]; my $r=$run->($child,$depth+1);
                if ($r eq 'ERROR') {$status='ERROR';last}
                if ($r eq 'RUNNING' || $r eq 'SUCCESS') {
                    $status=$r; $s->{runningChild}=$child;
                    if ($t eq 'PrioritySelector' && defined($previous) && $previous ne $child) {
                        my $h=_halt_node($previous,\%nodes,$runtime,$adapter,'priority preemption');
                        if ($h eq 'HALT_PENDING') {$runtime->{dispatchBlocked}=1}
                    }
                    last;
                }
            }
            if ($status ne 'RUNNING') { delete $s->{runningChild}; }
            if ($status eq 'FAILURE' && defined $previous && $t eq 'PrioritySelector') {
                my $h=_halt_node($previous,\%nodes,$runtime,$adapter,'priority branch no longer active');
                $runtime->{dispatchBlocked}=1 if $h eq 'HALT_PENDING';
            }
        } elsif ($t eq 'Sequence') {
            $status='SUCCESS';
            for my $child (@$children) {my $r=$run->($child,$depth+1);if($r eq 'ERROR'||$r eq 'FAILURE'){$status=$r;last}if($r eq 'RUNNING'){$status=$r;last}}
        } elsif ($t =~ /\A(?:Inverter|Cooldown|Timeout|Retry|AlwaysSucceed)\z/) {
            my $now=$snapshot->{now}//time; my $child=$children->[0];
            if ($t eq 'Cooldown' && defined($s->{until}) && $now < $s->{until}) {$status='FAILURE'}
            elsif ($t eq 'Timeout' && defined($s->{started}) && ($now-$s->{started})*1000 >= $p->{timeoutMs}) {
                my $h=_halt_node($child,\%nodes,$runtime,$adapter,'timeout');
                if ($h eq 'HALT_PENDING') {$status='RUNNING';$runtime->{dispatchBlocked}=1} else {$status='FAILURE';delete $s->{started}}
            } elsif ($t eq 'Retry' && defined($s->{retryAt}) && $now < $s->{retryAt}) {$status='RUNNING'}
            else {
                $s->{started}=$now if $t eq 'Timeout' && !defined $s->{started};
                $status=$run->($child,$depth+1);
                if ($t eq 'Inverter') {$status=$status eq 'SUCCESS'?'FAILURE':$status eq 'FAILURE'?'SUCCESS':$status}
                if ($t eq 'AlwaysSucceed' && $status eq 'FAILURE') {$status='SUCCESS'}
                if ($t eq 'Cooldown' && $status eq 'SUCCESS') {$s->{until}=$now+$p->{durationMs}/1000}
                if ($t eq 'Retry') {if($status eq 'FAILURE'){my $a=($s->{attempt}//0)+1;if($a<$p->{attempts}){$s->{attempt}=$a;$s->{retryAt}=$now+$p->{intervalMs}/1000;$status='RUNNING'}else{delete $s->{attempt};delete $s->{retryAt}}}elsif($status eq 'SUCCESS'){delete $s->{attempt};delete $s->{retryAt}}}
                delete $s->{started} if $t eq 'Timeout' && $status ne 'RUNNING';
            }
        } elsif ($ACTION{$t}) {
            $status=_action($id,$t,$p,$snapshot,$runtime,$adapter,$graph);
        } elsif ($t =~ /\A(?:CharacterHp|CharacterSp|WeightPercent|IsSitting|InMap|AggressivesNearby|StatusEffect|InventoryCount|MonsterNearby|CanAccessStorage|HasSkill|ActionIdle)\z/) {
            $status=_condition($t,$p,$snapshot);
        } elsif ($t eq 'Idle') {$status='RUNNING'}
        else {$status='ERROR';$s->{reason}='tipo de nó sem implementação'}
        $s->{reason}='sensor ou estado necessário indisponível' if $status eq 'ERROR' && !$s->{reason};
        my $entry={nodeId=>$id,status=>$status};$entry->{reason}=$s->{reason} if defined $s->{reason};push @{$runtime->{trace}},$entry;
        return $status;
    };
    my $ok=eval {$run->($graph->{rootId},1)};
    return {status=>$@?'ERROR':$ok,trace=>$runtime->{trace},runtime=>$runtime,error=>$@||undef};
}

sub _action {
    my ($id,$type,$params,$snapshot,$runtime,$adapter,$graph)=@_;
    my $state=$runtime->{nodes}{$id}; my $now=$snapshot->{now}//time;
    if ($type eq 'Wait') {$state->{until}//=$now+$params->{durationMs}/1000;my $v=$now >= $state->{until}?'SUCCESS':'RUNNING';delete $state->{until} if $v eq 'SUCCESS';return $v}
    # Shadow is deliberately read-only; never manufacture a successful action.
    if (($graph->{mode}//'shadow') eq 'shadow') {$state->{reason}='shadow: ação prevista, não enviada';return 'RUNNING'}
    return 'ERROR' unless $adapter && ref($adapter) eq 'HASH' && ref($adapter->{start}) eq 'CODE' && ref($adapter->{poll}) eq 'CODE';
    my $op=$state->{operation};
    if (!$op) {
        return 'RUNNING' if $runtime->{dispatchBlocked} || _has_owned_operation($runtime);
        return 'RUNNING' if $runtime->{actionsStarted};
        my $opid=join(':',$id,++$runtime->{nextOperation});
        my $started=eval {$adapter->{start}->($type,$params,$snapshot,$opid)};
        if ($@ || ref($started) ne 'HASH' || !$started->{accepted}) {$state->{reason}=$@||($started->{reason}//'adapter refused action');return 'FAILURE'}
        $state->{operation}={id=>$opid,startedAt=>$now,deadline=>$now+($params->{timeoutMs}//30000)/1000,token=>$started->{token},type=>$type};
        $runtime->{actionsStarted}=1;
        return 'RUNNING';
    }
    if (!$op->{haltPending} && $now >= $op->{deadline}) {
        my $h=_cancel($adapter,$op,'action timeout');
        if ($h eq 'HALTED') {delete $state->{operation};$state->{reason}='action timed out without completion evidence';return 'FAILURE'}
        $op->{haltPending}=1;$op->{haltUntil}=$now+2; $runtime->{dispatchBlocked}=1;
    }
    if ($op->{haltPending} && $now >= $op->{haltUntil}) {$runtime->{dispatchBlocked}=1;$state->{reason}='cancellation ownership remains unresolved';return 'ERROR'}
    my $result=eval {$adapter->{poll}->($op->{id},$op->{token},$snapshot)};
    if ($@ || !defined $result || $result !~ /\A(?:RUNNING|SUCCESS|FAILURE|ERROR|HALTED)\z/) {$state->{reason}='adapter returned invalid outcome';return 'ERROR'}
    if ($result eq 'HALTED' && $op->{haltPending}) {delete $state->{operation};delete $state->{reason};return 'FAILURE'}
    if ($op->{haltPending}) {$runtime->{dispatchBlocked}=1;return 'RUNNING'}
    if ($result ne 'RUNNING') {delete $state->{operation};delete $state->{reason}}
    return $result;
}
sub _reconcile_halts {my($runtime,$snapshot,$adapter)=@_;for my $n(values %{$runtime->{nodes}||{}}){next unless ref($n) eq 'HASH'&&$n->{operation}&&$n->{operation}{haltPending};my $op=$n->{operation};my $now=$snapshot->{now}//time;if($now >= ($op->{haltUntil}//$now)){ $runtime->{dispatchBlocked}=1;$n->{reason}='cancellation ownership remains unresolved';next }my $r=eval{$adapter->{poll}->($op->{id},$op->{token},$snapshot)} if $adapter&&ref($adapter->{poll}) eq 'CODE';if(!$@&&defined($r)&&$r eq 'HALTED'){delete $n->{operation};delete $n->{haltPending};delete $n->{reason}}else{$runtime->{dispatchBlocked}=1}}}
sub _has_owned_operation {my($runtime)=@_;for my $n(values %{$runtime->{nodes}||{}}){return 1 if ref($n) eq 'HASH' && $n->{operation}}return 0}
sub _cancel {my($a,$op,$why)=@_;return 'HALT_PENDING' unless $a && ref($a->{cancel}) eq 'CODE';my $r=eval{$a->{cancel}->($op->{id},$op->{token},$why)};return $@?'HALT_PENDING':($r//'HALT_PENDING')}
sub _halt_node {
    my($id,$nodes,$runtime,$adapter,$why)=@_;my $n=$nodes->{$id} or return 'HALTED';my $s=$runtime->{nodes}{$id}||{};my $result='HALTED';
    if ($s->{operation}) {$result=_cancel($adapter,$s->{operation},$why);if($result eq 'HALTED'){delete $s->{operation}}else{$s->{haltPending}=1}}
    for my $c (@{$n->{children}||[]}) {my $r=_halt_node($c,$nodes,$runtime,$adapter,$why);$result='HALT_PENDING' if $r eq 'HALT_PENDING'}
    return $result;
}
sub halt {my($graph,$runtime,$adapter,$why)=@_;my %n=map{$_->{id}=>$_}@{$graph->{nodes}||[]};return _halt_node($graph->{rootId},\%n,$runtime,$adapter,$why||'halt requested')}
sub _condition {
    my($t,$p,$s)=@_;my$status;
    my %field=(CharacterHp=>'hpPercent',CharacterSp=>'spPercent',WeightPercent=>'weightPercent',IsSitting=>'isSitting',InMap=>'map');my$key=$field{$t};
    if($t eq 'AggressivesNearby'){my$m=$s->{aggressives};return 'ERROR' unless ref($m) eq 'ARRAY';my@v=grep{defined($_->{definition}) && ($_->{definition} eq $p->{definition} || $_->{definition} eq 'either' || $p->{definition} eq 'either')}@$m;return 'ERROR' if grep{!defined($_->{distance})||($p->{requireLOS}&&!defined($_->{hasLOS}))}@v;my@x=grep{$_->{distance}<=$p->{distance}&&(!$p->{requireLOS}||$_->{hasLOS})}@v;return @x >= $p->{count}?'SUCCESS':'FAILURE'}
    if($t eq 'StatusEffect'){my$v=$s->{statusFlags};return 'ERROR' unless ref($v) eq 'HASH'&&exists $v->{$p->{statusId}};return (!!$v->{$p->{statusId}}==!!$p->{active})?'SUCCESS':'FAILURE'}
    if($t eq 'InventoryCount'){my$v=$s->{inventory};return 'ERROR' unless ref($v) eq 'HASH';return 'ERROR' if !exists($v->{$p->{itemId}})&&!$s->{inventoryComplete};my$c=$v->{$p->{itemId}};my$num=defined($c)?(ref($c) eq 'HASH'?$c->{amount}:$c):0;return 'ERROR' unless defined $num;return _compare($num,$p->{operator},$p->{count})?'SUCCESS':'FAILURE'}
    if($t eq 'MonsterNearby'){my$m=$s->{monstersVisible};return 'ERROR' unless ref($m) eq 'ARRAY';my%ids=map{$_=>1}@{$p->{monsterIds}||[]};my@v=grep{!%ids||$ids{$_->{nameId}//''}}@$m;return 'ERROR' if grep{!defined($_->{distance})||($p->{requireLOS}&&!defined($_->{hasLOS}))}@v;my@x=grep{$_->{distance}<=$p->{distance}&&(!$p->{requireLOS}||$_->{hasLOS})}@v;return @x >= $p->{count}?'SUCCESS':'FAILURE'}
    if($t eq 'CanAccessStorage'){return 'ERROR' unless exists $s->{canAccessStorage};return $s->{canAccessStorage}?'SUCCESS':'FAILURE'}
    if($t eq 'HasSkill'){my$v=$s->{skills};return 'ERROR' unless ref($v) eq 'HASH'&&exists $v->{$p->{skillHandle}};return $v->{$p->{skillHandle}}>=$p->{level}?'SUCCESS':'FAILURE'}
    if($t eq 'ActionIdle'){my$v=$s->{actionIdle};return 'ERROR' unless ref($v) eq 'HASH'&&exists $v->{$p->{domain}};return $v->{$p->{domain}}?'SUCCESS':'FAILURE'}
    return 'ERROR' unless defined $key && exists $s->{$key};
    return (!!$s->{$key} == !!$p->{expected})?'SUCCESS':'FAILURE' if $t eq 'IsSitting';return $s->{$key} eq $p->{mapName}?'SUCCESS':'FAILURE' if $t eq 'InMap';
    return _compare($s->{$key},$p->{operator},$p->{percent})?'SUCCESS':'FAILURE';
}
sub _compare {my($a,$op,$b)=@_;return 0 unless defined $a;return $a<$b if $op eq '<';return $a<=$b if $op eq '<=';return $a>$b if $op eq '>';return $a>=$b if $op eq '>=';return $a==$b}
1;
