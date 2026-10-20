package VisualBT::NativeTasks;
use strict;
use warnings;
use Scalar::Util qw(refaddr);

my %SUPPORTED = (Stand => 'confirmedStand', Sit => 'confirmedStand', MoveOneTile => 'confirmedMove', MoveTo => 'confirmedRoute', TeleportRandom => 'confirmedTeleport');
sub required_capabilities { return [qw(confirmedStand confirmedMove confirmedRoute confirmedTeleport)] }
sub new {
    my ($class,%o)=@_;
    return bless { api=>$o{api} || _openkore_api(), enabled=>$o{enabled}?1:0, operations=>{} },$class;
}
sub as_hash { my($s)=@_; return {start=>sub{$s->start(@_)},poll=>sub{$s->poll(@_)},cancel=>sub{$s->cancel(@_)}} }

sub _openkore_api {
    return {
        state=>sub { require AI; AI::state() }, auto=>sub { require AI; AI::AUTO() },
        connected=>sub { require Globals; require Network; $Globals::conState == Network::IN_GAME() },
        char=>sub { $Globals::char }, field=>sub { $Globals::field },
        queue=>sub { \@AI::ai_seq }, args=>sub { \@AI::ai_seq_args },
        make_task=>sub {
            my($type,$p,$c)=@_; my $actor=$c->{char};
            if($type eq 'Stand'||$type eq 'Sit'){require Task::SitStand;return Task::SitStand->new(actor=>$actor,mode=>lc($type),wait=>0)}
            if($type eq 'MoveOneTile') {require Task::Move;my($x,$y)=@{$c->{position}}{qw(x y)};my$d=$p->{direction}//'auto';$d='east' if$d eq'auto';$x++ if$d eq'east';$x-- if$d eq'west';$y++ if$d eq'north';$y-- if$d eq'south';return undef if$x<=0||$y<=0;return Task::Move->new(actor=>$actor,x=>$x,y=>$y)}
            if($type eq 'MoveTo'){require Task::Route;return Task::Route->new(field=>$c->{field},actor=>$actor,x=>$p->{x},y=>$p->{y})}
            if($type eq 'TeleportRandom'){require Task::Teleport::Random;return Task::Teleport::Random->new(actor=>$actor)}
            return undef;
        }, enqueue=>sub {require AI;AI::queue($_[0],$_[1])},
        done=>sub { require Task; $_[0]==Task::DONE() }, inactive=>sub { require Task; $_[0]==Task::INACTIVE() }, running=>sub { require Task; $_[0]==Task::RUNNING() || $_[0]==Task::INTERRUPTED() },
        unlink_owned=>\&_unlink_owned,
        position=>sub {my$c=shift;return undef unless ref($c->{pos}) eq 'HASH' && defined $c->{pos}{x} && defined $c->{pos}{y};return {x=>$c->{pos}{x},y=>$c->{pos}{y}}},
        field_name=>sub {my$f=shift;return $f->baseName},
    };
}
sub _ctx {
    my($api)=@_;my($char,$field)=($api->{char}->(),$api->{field}->());
    return unless $char&&$field&&$api->{connected}->()&&$api->{state}->()==$api->{auto}->();
    my$position=$api->{position}->($char);return unless ref($position) eq 'HASH' && defined $position->{x} && defined $position->{y};return {char=>$char,field=>$field,position=>$position};
}
sub start {
    my($s,$type,$p,$snap,$id)=@_;my$a=$s->{api};
    return {accepted=>0,reason=>'native tasks disabled'} unless $s->{enabled};
    return {accepted=>0,reason=>'unsupported native action'} unless $SUPPORTED{$type};
    return {accepted=>0,reason=>'operation already owned'} if keys %{$s->{operations}};
    return {accepted=>0,reason=>'native character unavailable or AI not AUTO'} unless my$c=_ctx($a);
    return {accepted=>0,reason=>'character is dead'} if $c->{char}{dead};
    my$q=$a->{queue}->();my$args=$a->{args}->();return {accepted=>0,reason=>'AI queue conflict'} if @$q||@$args;
    if ($type eq 'MoveOneTile') {
        my %dir=(east=>[1,0],west=>[-1,0],north=>[0,1],south=>[0,-1]);
        my @directions=($p->{direction}//'auto') eq 'auto' ? qw(east north west south) : ($p->{direction});
        my $chosen;
        for my $d (@directions) {
            next unless exists $dir{$d};
            my ($x,$y)=($c->{position}{x}+$dir{$d}[0],$c->{position}{y}+$dir{$d}[1]);
            next if $x<=0 || $y<=0;
            my $reachable=eval{$c->{field}->canMove($c->{position},{x=>$x,y=>$y})};
            next if $@ || !$reachable;
            $chosen=$d;last;
        }
        return {accepted=>0,reason=>'no reachable adjacent cell'} unless $chosen;
        $p={%$p,direction=>$chosen};
    }
    return {accepted=>0,reason=>'invalid task parameters'} if $type eq 'MoveTo' && (($p->{map}//'') ne $a->{field_name}->($c->{field}) || !defined$p->{x} || !defined$p->{y});
    my$t=eval{$a->{make_task}->($type,$p,$c)};return {accepted=>0,reason=>'native task creation failed'} if$@||!$t;
    my$startpos=$c->{position};my$startmap=$a->{field_name}->($c->{field});
    my($action)= $type eq'Stand' ? ('standing') : $type eq'Sit' ? ('sitting') : $type eq'MoveOneTile' ? ('move') : $type eq'MoveTo' ? ('route') : ('teleport');
    $a->{enqueue}->($action,$t);
    $s->{operations}{$id}={task=>$t,type=>$type,action=>$action,char=>$c->{char},startpos=>$startpos,startmap=>$startmap,target=>_target($type,$p,$startpos)};
    return {accepted=>1,token=>refaddr($t)};
}
sub _target {my($t,$p,$pos)=@_;return {x=>$p->{x},y=>$p->{y}} if$t eq'MoveTo';return undef unless$t eq'MoveOneTile';my($x,$y)=($pos->{x},$pos->{y});my$d=$p->{direction}//'auto';$d='east'if$d eq'auto';$x++if$d eq'east';$x--if$d eq'west';$y++if$d eq'north';$y--if$d eq'south';return{x=>$x,y=>$y}}
sub poll {
    my($s,$id,$token)=@_;my$o=$s->{operations}{$id}or return'HALTED';return'ERROR'unless defined$token&&$token==refaddr($o->{task});
    my$t=$o->{task};my$a=$s->{api};my$status=eval{$t->getStatus};return'ERROR'if$@;
    if($a->{done}->($status)){my$err=eval{$t->getError};my$good=!$@&&!$err&&_corroborated($o,$a);delete$s->{operations}{$id};return$good?'SUCCESS':'FAILURE'}
    if(!$a->{inactive}->($status)&&!$a->{running}->($status)){delete$s->{operations}{$id};return'FAILURE'}
    return'FAILURE' unless _is_queued($a,$o);
    return'RUNNING';
}
sub _corroborated {
    my($o,$a)=@_;my$c=$o->{char};my$type=$o->{type};
    return !$c->{sitting} if$type eq'Stand';return !!$c->{sitting} if$type eq'Sit';
    if($type eq'TeleportRandom'){return 0 unless $o->{task}{mapChanged};my$pos=eval{$a->{position}->($c)};return 1 if ($a->{field_name}->($a->{field}->())//'') ne $o->{startmap};return ref($pos) eq 'HASH' && ($pos->{x}!=$o->{startpos}{x} || $pos->{y}!=$o->{startpos}{y})}
    my$p=eval{$a->{position}->($c)};return 0 unless ref$p eq'HASH';
    return $p->{x}==$o->{target}{x}&&$p->{y}==$o->{target}{y} if$type eq'MoveTo';
    return ($p->{x}!=$o->{startpos}{x}||$p->{y}!=$o->{startpos}{y}) && $p->{x}==$o->{target}{x}&&$p->{y}==$o->{target}{y};
}
sub _is_queued {my($a,$o)=@_;my$q=$a->{queue}->();my$args=$a->{args}->();for my$i(0..$#$args){return 1 if defined$q->[$i]&&$q->[$i]eq$o->{action}&&ref($args->[$i])&&refaddr($args->[$i])==refaddr($o->{task})}return 0}
sub _unlink_owned {my($action,$task)=@_;for my$i(0..$#AI::ai_seq_args){next unless defined$AI::ai_seq[$i]&&$AI::ai_seq[$i]eq$action&&ref($AI::ai_seq_args[$i])&&refaddr($AI::ai_seq_args[$i])==refaddr($task);splice@AI::ai_seq,$i,1;splice@AI::ai_seq_args,$i,1;return 1}return 0}
sub cancel {
    my($s,$id,$token)=@_;my$o=$s->{operations}{$id}or return'HALTED';return'HALT_PENDING'unless defined$token&&$token==refaddr($o->{task});
    my$a=$s->{api};my$removed=eval{$a->{unlink_owned}->($o->{action},$o->{task})};return'HALT_PENDING'if$@||!$removed;
    my$status=eval{$o->{task}->getStatus};if(!$@&&($a->{inactive}->($status)||$a->{running}->($status))){eval{$o->{task}->stop};return'HALT_PENDING'if$@}
    delete$s->{operations}{$id};return'HALTED';
}
1;
