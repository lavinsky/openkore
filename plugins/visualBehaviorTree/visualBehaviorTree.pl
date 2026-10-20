package visualBehaviorTree;
use strict;
use warnings;
use File::Spec;
use JSON::PP;
use Time::HiRes qw(time clock_gettime CLOCK_MONOTONIC);
use Log qw(message warning);
use Globals qw($char $field $conState %config $monstersList %monstersTable);
use AI ();
use lib File::Spec->catdir($Plugins::current_plugin_folder || 'plugins/visualBehaviorTree','lib');
use VisualBT::Engine qw(tick halt);
use VisualBT::OpenKoreReader qw(build_openkore_snapshot);
use VisualBT::OpenKoreSensors qw(observe_monsters);
use VisualBT::NativeTasks;
use VisualBT::Validator qw(validate_graph);
use VisualBT::Persistence qw(read_json atomic_json);

my ($hooks,$command_id,$root,$active,$runtime,$last_io,$last_tick,$last_deploy_check,$last_deploy_meta,$events,$tick_count,$last_result,$seen_revision,$native_adapter);
my $mode='shadow'; my $revision=''; my $requested_revision=''; my $rejected_revision=''; my $validation_errors=[]; my $paused=0; my $last_error=''; my $instance=join('-',time,$$);
my $base=File::Spec->catdir($Plugins::current_plugin_folder || 'plugins/visualBehaviorTree');
my $control=File::Spec->catdir('control','behaviorTree');
sub _catalog { return read_json(File::Spec->catfile($base,'catalog','nodes.schema.json'),262144) }
sub _catalog_for_native_assist {
    my($catalog)=@_;return $catalog unless $config{visualBT_enableNativeTasks};
    my$copy=eval{JSON::PP->new->decode(JSON::PP->new->encode($catalog))};return $catalog unless ref($copy) eq 'HASH';
    my%native=map{$_=>1}qw(Stand Sit MoveOneTile MoveTo TeleportRandom);
    for my$n(@{$copy->{nodes}||[]}){$n->{requiredCapabilities}=[] if $native{$n->{typeId}//''}}
    return$copy;
}
sub _storage_ok { for my $p (File::Spec->catdir('control'),$control,File::Spec->catdir($control,'deployments'),File::Spec->catdir($control,'runtime')) {return 0 if -l $p} return -d File::Spec->catdir($control,'deployments') && -d File::Spec->catdir($control,'runtime') }
sub _emit { my ($kind,$data)=@_; $events ||= []; push @$events,{at=>time,kind=>$kind,data=>$data}; shift @$events while @$events>100 }
sub _status {
    my ($force)=@_; return if !$force && time-($last_io||0)<0.5; $last_io=time;
    return unless _storage_ok();
    my $file=File::Spec->catfile($control,'runtime','status.json');
    my $ai='unknown'; eval {$ai=AI::state()==AI::AUTO?'AUTO':AI::state()==AI::MANUAL?'MANUAL':'OFF'};
    my $trace=$last_result&&$last_result->{trace}?$last_result->{trace}:[];
    atomic_json($file,{protocolVersion=>1,timestamp=>time,instanceId=>$instance,aiState=>$ai,connectionState=>$conState?'connected':'disconnected',activeRevision=>$revision,requestedRevision=>$requested_revision,mode=>$mode,managedDomains=>[],treeState=>$paused?'PAUSED':($last_result?$last_result->{status}:'IDLE'),activeNodeIds=>[map {$_->{nodeId}} @$trace],currentOperation=>undef,lastError=>$last_error,metrics=>{ticks=>$tick_count||0},ackCommandId=>undef,rejectedRevision=>$rejected_revision,validationErrors=>$validation_errors}) if -d File::Spec->catdir($control,'runtime');
    if (@$events && -d File::Spec->catdir($control,'runtime')) { my $ef=File::Spec->catfile($control,'runtime','events.ndjson'); if(!-l $ef && open my $fh,'>>:raw',$ef){if((-s $ef||0)>5242880){close $fh;unlink $ef;open $fh,'>>:raw',$ef}for my $e(@$events){print {$fh} JSON::PP->new->canonical->encode($e)."\n"}close $fh;chmod 0600,$ef}$events=[] }
}
sub _reload {
    return unless _storage_ok();
    my ($force)=@_; return if !$force && time-($last_deploy_check||0)<0.25; $last_deploy_check=time;
    my $path=File::Spec->catfile($control,'deployments','current.json');
    my @st=lstat($path);return unless @st;return if -l _;
    my $meta=join(':',@st[1,7,9,10]);return if !$force && defined($last_deploy_meta) && $last_deploy_meta eq $meta;$last_deploy_meta=$meta;
    my $env=read_json($path,262144); return unless ref($env) eq 'HASH' && ($env->{revision}//'') ne ($seen_revision||'');
    $requested_revision=$env->{revision}; $seen_revision=$requested_revision;
    my $graph=$env->{profile}; my $cat=_catalog();
    if (!$cat) {$last_error='catalog missing';$rejected_revision=$requested_revision;$validation_errors=[$last_error];_emit('error',$last_error);return}
    my ($ok,$errors)=validate_graph($graph,_catalog_for_native_assist($cat));
    if (($graph->{mode}//'') ne 'shadow' && !(($graph->{mode}//'') eq 'assist' && $config{visualBT_enableNativeTasks})) {$ok=0;push @$errors,'assist exige visualBT_enableNativeTasks explícito'}
    if (!$ok) {$last_error=join('; ',@$errors);$rejected_revision=$requested_revision;$validation_errors=$errors;_emit('rejected',{revision=>$requested_revision,errors=>$errors});return}
    if($native_adapter && $active && $runtime){my$h=eval{halt($active,$runtime,$native_adapter->as_hash,'deployment replaced')};if($@||!defined($h)||$h ne'HALTED'){$last_error='owned native task cancellation pending';$rejected_revision=$requested_revision;$validation_errors=[$last_error];return}}
    $active=$graph; $revision=$requested_revision; $rejected_revision='';$validation_errors=[];$mode=$graph->{mode};
    $native_adapter=($mode eq 'assist' && $config{visualBT_enableNativeTasks}) ? VisualBT::NativeTasks->new(enabled=>1) : undef;
    $runtime={nodes=>{}}; $last_result=undef;$last_error=''; _emit('deployment-ack',{revision=>$revision,mode=>$mode});
}
sub _main_loop { eval {_reload();_status(0)}; if($@){$last_error='plugin loop error';} }
sub _visible_monsters { return observe_monsters($char,$field,$monstersList,\%monstersTable) }
sub _ai_pre { my $now=clock_gettime(CLOCK_MONOTONIC); return if ($mode ne 'shadow' && !($mode eq 'assist' && $native_adapter)) || $paused || !$active || !eval {AI::state()==AI::AUTO} || !$char || !$field || !$conState || $now-($last_tick||0)<0.1; $last_tick=$now; $tick_count++; my $observed=_visible_monsters(); my $snapshot=eval { build_openkore_snapshot($now,char=>$char,field=>$field,ai=>'AI',config=>\%config,connected=>1,monsters=>($observed ? $observed->{monsters} : undef),aggressives=>($observed ? $observed->{aggressives} : undef)) }; if($@ || !$snapshot){$last_error='snapshot unavailable';return} my $r=eval {tick($active,$snapshot,$runtime,$native_adapter?$native_adapter->as_hash:undef)}; if($@ || !$r){$last_error='evaluation failed';return} $last_result=$r;$last_error=$r->{status} eq 'ERROR'?'estado necessário indisponível':''; _emit('tick',{status=>$r->{status},trace=>$r->{trace}}); }
sub _command {
    my (undef,$arg)=@_; $arg||='status';
    if ($arg =~ /^\s*status\s*$/) { message "Behavior Tree: mode=$mode revision=".($revision||'(nenhuma)')." state=".($paused?'paused':'shadow')."\n"; }
    elsif ($arg =~ /^\s*pause\s*$/) {$paused=1;message "Behavior Tree pausada.\n"}
    elsif ($arg =~ /^\s*resume\s*$/) {$paused=0;message "Behavior Tree em shadow; nenhuma ação será enviada.\n"}
    elsif ($arg =~ /^\s*reload\s*$/) {$seen_revision='';$last_deploy_meta=undef;_reload(1);message "Behavior Tree recarregada em shadow.\n"}
    elsif ($arg =~ /^\s*stop\s*$/) {my$h=$native_adapter&&$active&&$runtime?eval{halt($active,$runtime,$native_adapter->as_hash,'user stop')}:'HALTED';if($@||!defined($h)||$h ne'HALTED'){message "Cancelamento da tarefa nativa pendente; execução não foi descartada.\n"}else{$paused=1;$runtime={nodes=>{}};message "Execução Behavior Tree parada.\n"}}
    elsif ($arg =~ /^\s*(?:help|diag)\s*$/) {message "Comandos: bt status|pause|resume|stop|reload|help\n"}
    else {message "Uso: bt status|pause|resume|stop|reload|help\n"}
}
sub _unload {
    eval{halt($active,$runtime,$native_adapter->as_hash,'plugin unload')} if $native_adapter&&$active&&$runtime;
    $active=undef;$runtime=undef;$native_adapter=undef;$paused=1;
    Plugins::delHooks($hooks) if $hooks;
    Commands::unregister($command_id) if $command_id;
    $hooks=undef;$command_id=undef;
}
Plugins::register('visualBehaviorTree','Editor visual Behavior Tree (shadow)',\&_unload,\&_unload);
$hooks=Plugins::addHooks(['mainLoop_pre',\&_main_loop,undef],['AI_pre',\&_ai_pre,undef],['AI_pre/manual',\&_main_loop,undef],['start3',\&_main_loop,undef]);
    $command_id=Commands::register(['bt','Visual Behavior Tree',\&_command]);
_reload();
1;
