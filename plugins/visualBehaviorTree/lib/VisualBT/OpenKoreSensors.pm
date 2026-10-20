package VisualBT::OpenKoreSensors;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(observe_monsters);

# Returns a complete, sanitized observation or undef. Partial visibility must
# never be interpreted as proof that no nearby aggressive monster exists.
sub observe_monsters {
    my ($char, $field, $monsters, $table) = @_;
    return unless $char && $field && $monsters && ref($table) eq 'HASH';
    return unless $char->can('position') && $field->can('checkLOS');
    my $origin = eval { $char->position() };
    return unless _valid_position($origin);
    my $actors = eval { $monsters->getItems() };
    return unless ref($actors) eq 'ARRAY' && @$actors <= 150;
    my (@visible, @aggressives);
    for my $mob (@$actors) {
        return unless $mob && $mob->can('position');
        my $pos = eval { $mob->position() };
        return unless _valid_position($pos);
        my ($dx,$dy) = (abs($origin->{x}-$pos->{x}),abs($origin->{y}-$pos->{y}));
        my $distance = $dx > $dy ? $dx : $dy;
        return if $@ || !defined($distance) || $distance < 0;
        my $los = eval { $field->checkLOS($origin, $pos, 0) };
        return if $@ || !defined($los);
        my $name_id = $mob->{nameID};
        return unless defined($name_id) && $name_id =~ /^[0-9]+$/;
        my %sensor = (nameID => 0+$name_id, distance => 0+$distance, hasLOS => $los ? 1 : 0);
        push @visible, \%sensor;
        my $type_aggressive = $table->{$name_id} && $table->{$name_id}{isAIMode_Aggressive} ? 1 : 0;
        my $attacking = defined($mob->{target}) && defined($char->{ID}) && $mob->{target} eq $char->{ID} ? 1 : 0;
        if ($type_aggressive || $attacking) {
            push @aggressives, {
                distance => 0+$distance,
                hasLOS => $los ? 1 : 0,
                attackingMe => $attacking,
                definition => $type_aggressive && $attacking ? 'either'
                    : $attacking ? 'attackingMe' : 'monsterTypeAggressive'
            };
        }
    }
    return { monsters => \@visible, aggressives => \@aggressives };
}
sub _valid_position {
    my ($p) = @_;
    return ref($p) eq 'HASH'
        && defined($p->{x}) && defined($p->{y})
        && $p->{x} =~ /^[0-9]+$/ && $p->{y} =~ /^[0-9]+$/;
}
1;
