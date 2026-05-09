#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use File::Glob qw(bsd_glob);
use Cwd 'abs_path';

my $env_file   = shift @ARGV or die "Usage: $0 <env-file> <input-yaml>\n";
my $input_file = shift @ARGV or die "Usage: $0 <env-file> <input-yaml>\n";

# -------------------------
# 1. Load .env
# -------------------------
my %env;

open my $efh, '<', $env_file or die "Cannot open $env_file: $!";
while (<$efh>) {
    chomp;
    next if /^\s*#/ || /^\s*$/;

    my ($k, $v) = split(/\s*=\s*/, $_, 2);
    next unless defined $k;

    $v =~ s/^["']//;
    $v =~ s/["']$//;

    $env{$k} = $v;
}
close $efh;

# -------------------------
# 2. Load SSH keys
# -------------------------
my @ssh_keys;

my $ssh_dir = "$ENV{HOME}/.ssh";

# authorized_keys
my $auth_keys = "$ssh_dir/authorized_keys";
if (-f $auth_keys) {
    open my $fh, '<', $auth_keys or die "Cannot open $auth_keys: $!";
    push @ssh_keys, grep { /\S/ } map { chomp; $_ } <$fh>;
    close $fh;
}

# *.pub files
for my $file (bsd_glob("$ssh_dir/*.pub")) {
    next unless -f $file;
    open my $fh, '<', $file or next;
    push @ssh_keys, grep { /\S/ } map { chomp; $_ } <$fh>;
    close $fh;
}

# deduplicate
my %seen;
@ssh_keys = grep { !$seen{$_}++ } @ssh_keys;

# -------------------------
# 3. Process YAML
# -------------------------
open my $in, '<', $input_file or die "Cannot open $input_file: $!";

while (my $line = <$in>) {
    chomp $line;

    # 3a. Inject SSH keys list
    if ($line =~ /^(\s*)(ssh_authorized_keys): *$/) {
        print "$1$2:\n";
        for my $key (@ssh_keys) {
            print "$1  - $key\n";
        }
        next;
    }

    # 3b. Replace env variables (simple token match)
    $line =~ s/\b([A-Z0-9_]+)\b/
        exists $env{$1} ? $env{$1} : $1
    /eg;

    print "$line\n";
}

close $in;
