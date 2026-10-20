package VisualBT::OpenKoreAdapter;
use strict;
use warnings;

# Injectable OpenKore facade. Deliberately disabled by default: task ownership
# and conflict policy have not been approved for assist mode.
sub new { my ($class,%o)=@_; bless {api=>$o{api}||{}, operations=>{}, enabled=>$o{enabled}?1:0},$class }
sub required_capabilities { return [] }
sub as_hash { my($self)=@_;return {start=>sub{$self->start(@_)},poll=>sub{$self->poll(@_)},cancel=>sub{$self->cancel(@_)}} }
sub start {
    my ($self,$type,$params,$snapshot,$opid)=@_;
    return {accepted=>0,reason=>'native actions disabled'} unless $self->{enabled};
    return {accepted=>0,reason=>'operation already owned'} if keys %{$self->{operations}};
    my $api=$self->{api};
    return {accepted=>0,reason=>'required native API unavailable'} unless $api->{start} && $api->{poll} && $api->{cancel};
    my $res=eval{$api->{start}->($type,$params,$snapshot,$opid)};
    return {accepted=>0,reason=>'native start failed'} if $@ || ref($res) ne 'HASH' || !$res->{accepted};
    $self->{operations}{$opid}={type=>$type,token=>$res->{token},started=>$snapshot};
    return {accepted=>1,token=>$res->{token}};
}
sub poll {
    my ($self,$id,$token,$snapshot)=@_;my $op=$self->{operations}{$id} or return 'HALTED';
    return 'ERROR' unless defined($token) && defined($op->{token}) && $token eq $op->{token};
    my $r=eval{$self->{api}{poll}->($op->{type},$id,$token,$snapshot,$op)};
    delete $self->{operations}{$id} if !$@ && defined($r) && $r =~ /\A(?:SUCCESS|FAILURE|HALTED)\z/;
    return $@?'ERROR':($r||'ERROR');
}
sub cancel {
    my ($self,$id,$token,$why)=@_;my $op=$self->{operations}{$id} or return 'HALTED';
    return 'HALT_PENDING' unless defined($token) && defined($op->{token}) && $token eq $op->{token};
    # Refuse unless the facade can prove that this exact token's task is ours.
    my $r=eval{$self->{api}{cancel}->($op->{type},$id,$token,$why,$op)};
    return 'HALT_PENDING' if $@ || !defined($r) || $r ne 'HALTED';
    delete $self->{operations}{$id};return 'HALTED';
}
1;
