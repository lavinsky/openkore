use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use VisualBT::OpenKoreSensors qw(observe_monsters);
use VisualBT::Engine qw(tick);

{ package BTTestActor;
  sub new { my ($class,%args)=@_; bless \%args,$class }
  sub position { $_[0]{pos} }
}
{ package BTTestField;
  sub new { bless {blocked=>$_[1]||{}},$_[0] }
  sub checkLOS { my ($s,$from,$to)=@_; return undef if $s->{unknown}; return $s->{blocked}{$to->{x}.','.$to->{y}} ? 0:1 }
}
{ package BTTestList;
  sub new { bless {items=>$_[1]},$_[0] }
  sub getItems { $_[0]{items} }
}

my $you=BTTestActor->new(ID=>'secret-gid',pos=>{x=>10,y=>10});
my $field=BTTestField->new({'13,10'=>1});
my $mobs=BTTestList->new([
  BTTestActor->new(nameID=>1408,target=>'secret-gid',pos=>{x=>12,y=>10},name=>'private'),
  BTTestActor->new(nameID=>1526,target=>'someone-else',pos=>{x=>13,y=>10}),
  BTTestActor->new(nameID=>1410,pos=>{x=>11,y=>10}),
]);
my $table={1408=>{isAIMode_Aggressive=>1},1526=>{isAIMode_Aggressive=>1},1410=>{isAIMode_Aggressive=>0}};
my $r=observe_monsters($you,$field,$mobs,$table);
ok($r, 'a complete map observation is created');
is(scalar @{$r->{monsters}},3,'all visible monsters observed');
is(scalar @{$r->{aggressives}},2,'only attacking or type-aggressive mobs counted');
is($r->{aggressives}[0]{definition},'either','both attacking and aggressive type represented once');
is($r->{aggressives}[1]{hasLOS},0,'wall blocks LOS');
ok(!exists $r->{monsters}[0]{name} && !exists $r->{monsters}[0]{ID},'raw actor names and IDs excluded');
my $root='check';
my $graph={mode=>'shadow',rootId=>$root,nodes=>[{id=>$root,type=>'AggressivesNearby',params=>{count=>1,distance=>9,requireLOS=>1,definition=>'attackingMe'},children=>[]}]};
is(tick($graph,{aggressives=>$r->{aggressives}},{})->{status},'SUCCESS','attacker behind available LOS triggers danger');
$graph->{nodes}[0]{params}{definition}='monsterTypeAggressive';
is(tick($graph,{aggressives=>$r->{aggressives}},{})->{status},'SUCCESS','both category also matches type aggressive');
$graph->{nodes}[0]{params}{count}=2;
is(tick($graph,{aggressives=>$r->{aggressives}},{})->{status},'FAILURE','two visible aggressives require LOS of both');
$field->{unknown}=1;
ok(!defined observe_monsters($you,$field,$mobs,$table),'unknown LOS invalidates entire sensor, not false safety');
delete $field->{unknown};
$mobs->{items}[0]{pos}=undef;
ok(!defined observe_monsters($you,$field,$mobs,$table),'unknown monster coordinates invalidate sensor');
done_testing;
