use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use VisualBT::Validator qw(validate_graph);
use VisualBT::Engine qw(tick);
my $catalog=JSON::PP->new->decode(do {local $/;open my $f,'<',"$FindBin::Bin/../catalog/nodes.schema.json" or die $!;<$f>});
sub node {my($id,$type,$params,$children)=@_;return{id=>$id,type=>$type,params=>$params||{},children=>$children||[]}}
my $g={schemaVersion=>1,profileId=>'test',name=>'Test',description=>'',mode=>'shadow',managedDomains=>[],rootId=>'root',nodes=>[
 node('root','PrioritySelector',{},['high','low']),node('high','Sequence',{},['cond','wait']),node('cond','WeightPercent',{operator=>'>=',percent=>48}),node('wait','Wait',{durationMs=>100}),node('low','Idle') ]};
my($ok,$errs)=validate_graph($g,$catalog);ok($ok,'valid graph accepted') or diag join("\n",@$errs);
my $rt={nodes=>{}};my $r=tick($g,{weightPercent=>49,now=>10},$rt);is($r->{status},'RUNNING','sequence waits asynchronously');
$r=tick($g,{weightPercent=>49,now=>10.05},$rt);is($r->{status},'RUNNING','priority selector remains on first running branch');
$r=tick($g,{weightPercent=>47,now=>10.3},$rt);is($r->{status},'RUNNING','reactive priority selects fallback');
my $bad={%$g,nodes=>[@{$g->{nodes}},node('orphan','Idle')]};($ok,$errs)=validate_graph($bad,$catalog);ok(!$ok,'orphan rejected');
$bad={%$g,nodes=>[@{$g->{nodes}}]};$bad->{nodes}[0]{children}=['root'];($ok,$errs)=validate_graph($bad,$catalog);ok(!$ok,'cycle rejected');
my $errgraph={schemaVersion=>1,profileId=>'x',name=>'x',description=>'',mode=>'shadow',managedDomains=>[],rootId=>'inv',nodes=>[node('inv','Inverter',{},['missing'])]};
$r=tick($errgraph,{},{});is($r->{status},'ERROR','ERROR is never inverted to success');
my $hpgraph={schemaVersion=>1,profileId=>'x',name=>'x',description=>'',mode=>'shadow',managedDomains=>[],rootId=>'hp',nodes=>[node('hp','CharacterHp',{operator=>'<',percent=>50})]};
$r=tick($hpgraph,{},{});is($r->{status},'ERROR','sensor ausente não é inferido');
$r=tick($hpgraph,{hpPercent=>49},{});is($r->{status},'SUCCESS','sensor presente é avaliado');
my $actiongraph={schemaVersion=>1,profileId=>'x',name=>'x',description=>'',mode=>'shadow',managedDomains=>[],rootId=>'action',nodes=>[node('action','AttackTarget',{monsterIds=>[1410],timeoutMs=>1000})]};
$r=tick($actiongraph,{},{});is($r->{status},'RUNNING','ação prevista no shadow permanece pendente');is($r->{runtime}{actionsStarted},0,'shadow não despacha ação externa');
my $losgraph={schemaVersion=>1,profileId=>'x',name=>'x',description=>'',mode=>'shadow',managedDomains=>[],rootId=>'los',nodes=>[node('los','MonsterNearby',{monsterIds=>[],distance=>9,requireLOS=>1,count=>1})]};
$r=tick($losgraph,{monstersVisible=>[{nameId=>1410,distance=>2}]},{});is($r->{status},'ERROR','LOS ausente não é tratado como LOS bloqueado');
my $boolgraph=JSON::PP->new->decode('{"schemaVersion":1,"profileId":"bool","name":"bool","description":"","mode":"shadow","managedDomains":[],"rootId":"sit","nodes":[{"id":"sit","type":"IsSitting","params":{"expected":true},"children":[]}]}');
($ok,$errs)=validate_graph($boolgraph,$catalog);ok($ok,'booleano JSON validado') or diag join("\n",@$errs);
$boolgraph->{unexpected}=1;($ok,$errs)=validate_graph($boolgraph,$catalog);ok(!$ok,'campo de topo inesperado rejeitado');
my $assist={%$actiongraph,mode=>'assist'};($ok,$errs)=validate_graph($assist,$catalog);ok(!$ok,'modo assist bloqueado por capacidades indisponíveis');
my $invgraph={schemaVersion=>1,profileId=>'x',name=>'x',description=>'',mode=>'shadow',managedDomains=>[],rootId=>'inv',nodes=>[node('inv','Inverter',{},['cond']),node('cond','WeightPercent',{operator=>'>=',percent=>48})]};
$r=tick($invgraph,{weightPercent=>47},{});is($r->{status},'SUCCESS','Inverter: FAILURE becomes SUCCESS');
$r=tick($invgraph,{weightPercent=>49},{});is($r->{status},'FAILURE','Inverter: SUCCESS becomes FAILURE exactly once');

# Injected async adapter: request and poll are distinct ticks; enqueue alone is not success.
my $async_graph={%$actiongraph,mode=>'assist'};
my $calls=0;my $finished=0;my $cancelled=0;
my $adapter={start=>sub{$calls++;return{accepted=>1,token=>{owned=>1}}},poll=>sub{$finished?'SUCCESS':'RUNNING'},cancel=>sub{$cancelled++;'HALTED'}};
my $async_rt={nodes=>{}};
$r=tick($async_graph,{now=>1},$async_rt,$adapter);is($r->{status},'RUNNING','native request stays running after dispatch');is($calls,1,'one request dispatched');
$r=tick($async_graph,{now=>1.1},$async_rt,$adapter);is($r->{status},'RUNNING','pending request polled without redispatch');is($calls,1,'pending operation is not resent');
$finished=1;$r=tick($async_graph,{now=>1.2},$async_rt,$adapter);is($r->{status},'SUCCESS','success requires adapter completion evidence');
my $timeout_rt={nodes=>{}};$finished=0;$r=tick($async_graph,{now=>2},$timeout_rt,$adapter);$r=tick($async_graph,{now=>4},$timeout_rt,$adapter);is($r->{status},'FAILURE','unknown action outcome times out as failure');
my $pending_cancel_adapter={%$adapter,cancel=>sub{$cancelled++;'HALT_PENDING'}};
my $preempt_graph={%$g,mode=>'assist',nodes=>[node('root','PrioritySelector',{},['high','low']),node('high','Sequence',{},['guard','act']),node('guard','WeightPercent',{operator=>'>=',percent=>48}),node('act','AttackTarget',{monsterIds=>[1410],timeoutMs=>5000}),node('low','Idle')]};
my $preempt_rt={nodes=>{}};$r=tick($preempt_graph,{weightPercent=>50,now=>10},$preempt_rt,$pending_cancel_adapter);$r=tick($preempt_graph,{weightPercent=>1,now=>10.1},$preempt_rt,$pending_cancel_adapter);ok($cancelled>0,'priority preemption asks adapter to cancel owned operation');is($r->{runtime}{dispatchBlocked},1,'pending cancellation blocks conflicting dispatch');

use VisualBT::Snapshot qw(build_snapshot);
use VisualBT::OpenKoreReader qw(build_openkore_snapshot);
use VisualBT::OpenKoreAdapter;
my $snap=build_snapshot({hpPercent=>sub{(0,0)},weightPercent=>sub{(49.5,1)},position=>sub{({x=>2,y=>4},1)},monstersVisible=>sub{([{ID=>'SECRET',name=>'private',nameId=>1001,distance=>3,hasLOS=>1}],1)},inventory=>sub{({501=>2},1)}},123);
ok(!exists($snap->{hpPercent}),'unready sensor omitted');is($snap->{weightPercent},49.5,'ready numeric sensor retained');is_deeply($snap->{position},{x=>2,y=>4},'position sanitized');ok(!exists($snap->{monstersVisible}[0]{ID}),'private actor id stripped');ok(!exists($snap->{monstersVisible}[0]{name}),'private actor name stripped');is($snap->{inventory}{501}{amount},2,'inventory represented by safe item/count');
{ package MockYou; sub hp_percent{77} sub sp_percent{35} sub weight_percent{48} sub position{{x=>10,y=>20}} }
{ package MockField; sub baseName{'gonryun'} }
{ package MockAI; sub state{2} sub action{'route'} }
my $native=build_openkore_snapshot(9,char=>bless({sitting=>0,dead=>0},'MockYou'),field=>bless({},'MockField'),ai=>'MockAI',config=>{storageAuto=>1,storageAuto_npc=>'gonryun'},connected=>1,monsters=>[{nameID=>1001,distance=>3,hasLOS=>1,ID=>'PRIVATE'}]);
is($native->{weightPercent},48,'native reader exposes weight threshold');is($native->{map},'gonryun','native reader exposes map');is($native->{aiState},'AUTO','native reader maps OpenKore AI state');is($native->{monstersVisible}[0]{nameId},1001,'native reader exposes visible monster type');ok(!exists($native->{monstersVisible}[0]{ID}),'native reader omits actor ID');
my $disabled=VisualBT::OpenKoreAdapter->new(enabled=>0,api=>{start=>sub{fail('disabled adapter dispatched')}});my $refused=$disabled->start('Stand',{}, {},'op1');ok(!$refused->{accepted},'native adapter disabled pending ownership policy');is_deeply($disabled->required_capabilities,[],'no unproven action capability advertised');

done_testing;
