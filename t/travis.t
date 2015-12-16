#!/usr/bin/env perl

use 5.16.0;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Capture::Tiny qw/ capture_merged /;
use FindBin '$RealBin';

if (defined $ENV{TRAVIS} and $ENV{TRAVIS} eq 'true') {
	plan tests => 26;
} else {
	plan skip_all => 'Only run these tests under Travis CI (TRAVIS=true)';
}
$ENV{TEST_ONLINE} //= 0;

my $lib = "$RealBin/../SBO-Lib/lib";
my $path = "$RealBin/..";

sub run {
	my %args = (
		exit => 0,
		cmd => [],
		input => undef
		@_
	);
	note explain \%args;
	my $cmd = shift @{ $args{cmd} };
	return undef unless defined $cmd;
	my @cmd = ($^X, "-I$lib", "$path/$cmd", @{ $args{cmd} });
	my $exit = $args{exit};
	my ($output, $return) = capture_merged {
		my $ret;
		if (defined(my $input = $args{input})) {
			$ret = system(qw/bash -c/, "@cmd <<END\n$input\nEND\n") && $? >> 8;
		}
		else {
			$ret = system(@cmd) && $? >> 8;
		}
		$ret;
	};
	return $output if $return == $exit;
	return "Command $cmd ($path/$cmd) exited with $return instead of $exit";
}

# 1-3: Test SLACKWARE_VERSION
is (run(cmd => [qw/ sboconfig -V 14.1 /]), "Setting SLACKWARE_VERSION to 14.1...\n", 'setting SLACKWARE_VERSION works');
SKIP: {
	skip 'Not doing online tests without TEST_ONLINE=1', 2 if $ENV{TEST_ONLINE} ne '1';

	is (run(cmd => [qw/ sbosnap fetch /]), "Pulling SlackBuilds tree...\n", 'sbosnap fetch works');
	is (run(cmd => [qw/ sbofind sbotools /]), "SBo:    sbotools\nPath:   /usr/sbo/repo/system/sbotools\n\n", 'sbofind works');
}

# 4-10: Test alternative REPO
is (system(qw!rm -rf /usr/sbo!), 0, 'Removing /usr/sbo works');
ok (! -e "/usr/sbo/repo/SLACKBUILDS.TXT", "SLACKBUILDS.TXT doesn't exist");
is (run(cmd => [qw! sboconfig -r https://github.com/Ponce/slackbuilds.git !]), "Setting REPO to https://github.com/Ponce/slackbuilds.git...\n", 'setting REPO works');
SKIP: {
	skip 'Not doing online tests without TEST_ONLINE=1', 4 if $ENV{TEST_ONLINE} ne '1';

	like (run(cmd => [qw/ sbosnap fetch /]), qr!Pulling SlackBuilds tree.*Cloning into '/usr/sbo/repo'!s, 'sbosnap fetch works from alternative REPO');
	ok (-e "/usr/sbo/repo/SLACKBUILDS.TXT", "SLACKBUILDS.TXT exists (REPO)");
	ok (! -e "/usr/sbo/repo/SLACKBUILDS.TXT.gz", "SLACKBUILDS.TXT.gz doesn't exist (REPO)");
	is (run(cmd => [qw/ sbofind sbotools /]), "SBo:    sbotools\nPath:   /usr/sbo/repo/system/sbotools\n\n", 'sbofind works');
}

# 11-17: Test local overrides
is (run(cmd => [qw/ sboconfig -o /, "$RealBin/LO"]), "Setting LOCAL_OVERRIDES to $RealBin/LO...\n", 'setting LOCAL_OVERRIDES works');
my $skip = 0;
SKIP: {
	if ($ENV{TEST_ONLINE} ne '1') { $skip = !(system(qw! mkdir -p /usr/sbo/repo !) == 0 and system(qw! touch /usr/sbo/repo/SLACKBUILDS.TXT !) == 0) }
	skip "Online testing disabled (TEST_ONLINE!=1) and could not create dummy SLACKBUILDS.TXT", 9 if $skip;

	is (run(cmd => [qw/ sbofind nonexistentslackbuild /]), <<"LOCAL", "sbofind finds local overrides");
Local:  nonexistentslackbuild2
Path:   $RealBin/LO/nonexistentslackbuild2

Local:  nonexistentslackbuild
Path:   $RealBin/LO/nonexistentslackbuild

LOCAL
	like (run(cmd => [qw/ sboinstall -r nonexistentslackbuild /]),
		qr/nonexistentslackbuild added to install queue[.].*perf[.]dummy' saved.*Cleaning for nonexistentslackbuild-1[.]0/s, 'sboinstall works (LOCAL_OVERRIDES)');
	like (run(cmd => [qw/ sboremove --nointeractive nonexistentslackbuild /]), qr/Removing 1 package\(s\).*nonexistentslackbuild.*All operations have completed/s, 'sboremove works');
	is (system(qw!/sbin/installpkg nonexistentslackbuild-0.9-noarch-1_SBo.tgz!), 0, 'Old version fake installed');
	like (run(cmd => [qw/ sbocheck /]), qr/Updating SlackBuilds tree.*Checking for updated SlackBuilds.*nonexistentslackbuild 0[.]9.*needs updating/s, 'sbocheck finds old version');
	like (run(cmd => [qw/ sboupgrade -r nonexistentslackbuild /]),
		qr/nonexistentslackbuild added to upgrade queue.*Upgrade queue: nonexistentslackbuild/s, 'sboupgrade upgrades old version');

# 18: Test missing dep
	is (run(cmd => [qw/ sboisntall nonexistentslackbuilds2 /], input => 'y'),
		"Unable to locate nonexistentslackbuild3 in the SlackBuilds.org tree.\n", 'sboinstall nonexistentslackbuild2 has correct output');
}

# 19-23: Test sboupgrade --all
SKIP: {
	my @files = glob("/var/log/packages/nonexistentslackbuild-*");
	skip 'nonexistentslackbuild not installed', 1 if @files == 0;

	is (system(qw!/sbin/removepkg nonexistentslackbuild!), 0, 'removepkging nonexistentslackbuild works');
}
SKIP: {
	skip "Online testing disabled (TEST_ONLINE!=1) and could not create dummy SLACKBUILDS.txt", 4 if $skip;

	my @files = glob("/var/log/packages/nonexistentslackbuild-*");
	skip 'Cannot test if nonexistentslackbuild is already installed', 4 if @files;

	is (system(qw!/sbin/installpkg nonexistentslackbuild-0.9-noarch-1_SBo.tgz!), 0, 'installpkg old version works');
	like (run(cmd => [qw/ sboupgrade -r --all /]),
		qr/Checking for updated SlackBuilds.*nonexistentslackbuild added to upgrade queue.*Cleaning for nonexistentslackbuild/s, 'sboupgrade --all works');
	ok (-e "/var/log/packages/nonexistentslackbuild-1.0-noarch-1_SBo", 'updated package is installed');
	ok (! -e  "/var/log/packages/nonexistentslackbuild-0.9-noarch-1_SBo", 'old package is removed');
}

if (not glob("/var/log/packages/nonexistentslackbuild-*")) {
	run(cmd => [qw/ sboinstall -r nonexistentslackbuild /]);
}
if (not glob("/var/log/packages/nonexistentslackbuild4-*")) {
	run(cmd => [qw/ sboinstall nonexistentslackbuild4 /], input => "y\ny\ny");
}
# 24-25: Test sboupgrade -f
like (run(cmd => [qw/ sboupgrade -f nonexistentslackbuild /], input => "y\ny"), qr/Proceed with nonexistentslackbuild\?.*Upgrade queue: nonexistentslackbuild$/s, 'sboupgrade -f works');
like (run(cmd => [qw/ sboupgrade -f nonexistentslackbuild4 /], input => "y\ny"), qr/Proceed with nonexistentslackbuild4\?.*Upgrade queue: nonexistentslackbuild4$/s, 'sboupgrade -f with requirements works');

# 26: Test sboupgrade -f -z
like (run(cmd => [qw/ sboupgrade -f -z nonexistentslackbuild4 /], input => "y\ny\ny"),
	qr/nonexistentslackbuild5 added to upgrade queue.*nonexistentslackbuild4 added to upgrade queue.*Upgrade queue: nonexistentslackbuild5 nonexistentslackbuild4$/s,
	'sboupgrade -f -z works with requirements');

# Cleanup
capture_merged {
	system(qw!/sbin/removepkg nonexistentslackbuild!);
	system(qw!/sbin/removepkg nonexistentslackbuild4!);
	system(qw!/sbin/removepkg nonexistentslackbuild5!);
	unlink "$RealBin/LO/nonexistentslackbuild/perf.dummy";
	unlink "$RealBin/LO/nonexistentslackbuild4/perf.dummy";
	unlink "$RealBin/LO/nonexistentslackbuild5/perf.dummy";
};
