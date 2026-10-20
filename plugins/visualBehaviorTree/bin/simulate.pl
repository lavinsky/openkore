#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use VisualBT::Engine qw(tick);
use VisualBT::Validator qw(validate_graph);
my $raw=do {local $/;<STDIN>};
exit 2 if !defined($raw) || length($raw)>262144;
my $input=eval {JSON::PP->new->decode($raw)};
if ($@ || ref($input) ne 'HASH') {print JSON::PP->new->encode({error=>'Entrada JSON inválida'});exit 2}
open my $cf,'<',"$FindBin::Bin/../catalog/nodes.schema.json" or die 'catalog missing';
my $catalog=JSON::PP->new->decode(do {local $/;<$cf>});close $cf;
my($valid,$errors)=validate_graph($input->{profile},$catalog);
if(!$valid){print JSON::PP->new->encode({error=>'Perfil inválido',errors=>$errors});exit 1}
my $snapshot=$input->{snapshot}||{}; my $runtime={nodes=>{}};my @ticks;
my $now=$snapshot->{now}//0; $snapshot->{now}=$now;
for(1..20){my$r=tick($input->{profile},$snapshot,$runtime);push @ticks,{status=>$r->{status},trace=>$r->{trace}};last if $r->{status} ne 'RUNNING';$now+=0.25;$snapshot->{now}=$now}
print JSON::PP->new->encode({ticks=>\@ticks});
