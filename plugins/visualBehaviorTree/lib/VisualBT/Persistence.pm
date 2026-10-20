package VisualBT::Persistence;
use strict;
use warnings;
use JSON::PP;
use IO::Handle;
use File::Spec;
use Exporter 'import';
our @EXPORT_OK = qw(read_json atomic_json);
sub read_json { my ($path,$limit)=@_; return unless -f $path && !-l $path; my @s=stat($path); return if !$s[7] || $s[7] > ($limit||262144); open my $fh,'<:raw',$path or return; local $/; my $raw=<$fh>; close $fh; return eval { JSON::PP->new->utf8->decode($raw) } }
sub atomic_json { my ($path,$value)=@_; my $dir=(File::Spec->splitpath($path))[1]; return 0 unless -d $dir; my $tmp="$path.tmp.$$"; my $raw=eval { JSON::PP->new->utf8->canonical->encode($value) }; return 0 if $@; return 0 if length($raw)>5242880; return 0 unless open my $fh,'>:raw',$tmp; print {$fh} $raw or do {close $fh;unlink $tmp;return 0}; eval {$fh->sync}; close $fh or do {unlink $tmp;return 0}; chmod 0600,$tmp; rename $tmp,$path or do {unlink $tmp;return 0}; return 1 }
1;
