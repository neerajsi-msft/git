#!/bin/sh

test_description='git serialized status tests'

. ./test-lib.sh

# This file includes tests for serializing / deserializing
# status data. These tests cover two basic features:
#
# [1] Because users can request different types of untracked-file
#     and ignored file reporting, the cache data generated by
#     serialize must use either the same untracked and ignored
#     parameters as the later deserialize invocation; otherwise,
#     the deserialize invocation must disregard the cached data
#     and run a full scan itself.
#
#     To increase the number of cases where the cached status can
#     be used, we have added a "--untracked-file=complete" option
#     that reports a superset or union of the results from the
#     "-u normal" and "-u all".  We combine this with a filter in
#     deserialize to filter the results.
#
#     Ignored file reporting is simpler in that is an all or
#     nothing; there are no subsets.
#
#     The tests here (in addition to confirming that a cache
#     file can be generated and used by a subsequent status
#     command) need to test this untracked-file filtering.
#
# [2] ensuring the status calls are using data from the status
#     cache as expected.  This includes verifying cached data
#     is used when appropriate as well as falling back to
#     performing a new status scan when the data in the cache
#     is insufficient/known stale.

test_expect_success 'setup' '
	cat >.gitignore <<-\EOF &&
	*.ign
	ignored_dir/
	EOF

	mkdir tracked ignored_dir &&
	touch tracked_1.txt tracked/tracked_1.txt &&
	git add . &&
	test_tick &&
	git commit -m"Adding original file." &&
	mkdir untracked &&
	touch ignored.ign ignored_dir/ignored_2.txt \
	      untracked_1.txt untracked/untracked_2.txt untracked/untracked_3.txt
'

test_expect_success 'verify untracked-files=complete with no conversion' '
	test_when_finished "rm serialized_status.dat new_change.txt output" &&
	cat >expect <<-\EOF &&
	? expect
	? serialized_status.dat
	? untracked/
	? untracked/untracked_2.txt
	? untracked/untracked_3.txt
	? untracked_1.txt
	! ignored.ign
	! ignored_dir/
	EOF
	
	git status --untracked-files=complete --ignored=matching --serialize >serialized_status.dat &&
	touch new_change.txt &&

	git status --porcelain=v2 --untracked-files=complete --ignored=matching --deserialize=serialized_status.dat >output &&
	test_i18ncmp expect output
'

test_expect_success 'verify untracked-files=complete to untracked-files=normal conversion' '
	test_when_finished "rm serialized_status.dat new_change.txt output" &&
	cat >expect <<-\EOF &&
	? expect
	? serialized_status.dat
	? untracked/
	? untracked_1.txt
	EOF
	
	git status --untracked-files=complete --ignored=matching --serialize >serialized_status.dat &&
	touch new_change.txt &&

	git status --porcelain=v2 --deserialize=serialized_status.dat >output &&
	test_i18ncmp expect output
'

test_expect_success 'verify untracked-files=complete to untracked-files=all conversion' '
	test_when_finished "rm serialized_status.dat new_change.txt output" &&
	cat >expect <<-\EOF &&
	? expect
	? serialized_status.dat
	? untracked/untracked_2.txt
	? untracked/untracked_3.txt
	? untracked_1.txt
	! ignored.ign
	! ignored_dir/
	EOF
	
	git status --untracked-files=complete --ignored=matching --serialize >serialized_status.dat &&
	touch new_change.txt &&

	git status --porcelain=v2 --untracked-files=all --ignored=matching --deserialize=serialized_status.dat >output &&
	test_i18ncmp expect output
'

test_expect_success 'verify serialized status with non-convertible ignore mode does new scan' '
	test_when_finished "rm serialized_status.dat new_change.txt output" &&
	cat >expect <<-\EOF &&
	? expect
	? new_change.txt
	? output
	? serialized_status.dat
	? untracked/
	? untracked_1.txt
	! ignored.ign
	! ignored_dir/
	EOF
	
	git status --untracked-files=complete --ignored=matching --serialize >serialized_status.dat &&
	touch new_change.txt &&

	git status --porcelain=v2 --ignored --deserialize=serialized_status.dat >output &&
	test_i18ncmp expect output
'

test_expect_success 'verify serialized status handles path scopes' '
	test_when_finished "rm serialized_status.dat new_change.txt output" &&
	cat >expect <<-\EOF &&
	? untracked/
	EOF
	
	git status --untracked-files=complete --ignored=matching --serialize >serialized_status.dat &&
	touch new_change.txt &&

	git status --porcelain=v2 --deserialize=serialized_status.dat untracked >output &&
	test_i18ncmp expect output
'

test_expect_success 'verify no-ahead-behind and serialized status integration' '
	test_when_finished "rm serialized_status.dat new_change.txt output" &&
	cat >expect <<-\EOF &&
	# branch.oid 68d4a437ea4c2de65800f48c053d4d543b55c410
	# branch.head alt_branch
	# branch.upstream master
	# branch.ab +1 -0
	? expect
	? serialized_status.dat
	? untracked/
	? untracked_1.txt
	EOF

	git checkout -b alt_branch master --track >/dev/null &&
	touch alt_branch_changes.txt &&
	git add alt_branch_changes.txt &&
	test_tick &&
	git commit -m"New commit on alt branch"  &&

	git status --untracked-files=complete --ignored=matching --serialize >serialized_status.dat &&
	touch new_change.txt &&

	git -c status.aheadBehind=false status --porcelain=v2 --branch --ahead-behind --deserialize=serialized_status.dat >output &&
	test_i18ncmp expect output
'

test_expect_success 'verify new --serialize=path mode' '
	test_when_finished "rm serialized_status.dat expect new_change.txt output.1 output.2" &&
	cat >expect <<-\EOF &&
	? expect
	? output.1
	? untracked/
	? untracked_1.txt
	EOF

	git checkout -b serialize_path_branch master --track >/dev/null &&
	touch alt_branch_changes.txt &&
	git add alt_branch_changes.txt &&
	test_tick &&
	git commit -m"New commit on serialize_path_branch"  &&

	git status --porcelain=v2 --serialize=serialized_status.dat >output.1 &&
	touch new_change.txt &&

	git status --porcelain=v2 --deserialize=serialized_status.dat >output.2 &&
	test_i18ncmp expect output.1 &&
	test_i18ncmp expect output.2
'

test_expect_success 'try deserialize-wait feature' '
	test_when_finished "rm -f serialized_status.dat dirt expect.* output.* trace.*" &&

	git status --serialize=serialized_status.dat >output.1 &&

	# make status cache stale by updating the mtime on the index.  confirm that
	# deserialize fails when requested.
	sleep 1 &&
	touch .git/index &&
	test_must_fail git status --deserialize=serialized_status.dat --deserialize-wait=fail &&
	test_must_fail git -c status.deserializeWait=fail status --deserialize=serialized_status.dat &&

	cat >expect.1 <<-\EOF &&
	? expect.1
	? output.1
	? serialized_status.dat
	? untracked/
	? untracked_1.txt
	EOF

	# refresh the status cache.
	git status --porcelain=v2 --serialize=serialized_status.dat >output.1 &&
	test_cmp expect.1 output.1 &&

	# create some dirt. confirm deserialize used the existing status cache.
	echo x >dirt &&
	git status --porcelain=v2 --deserialize=serialized_status.dat >output.2 &&
	test_cmp output.1 output.2 &&

	# make the cache stale and try the timeout feature and wait upto
	# 2 tenths of a second.  confirm deserialize timed out and rejected
	# the status cache and did a normal scan.

	cat >expect.2 <<-\EOF &&
	? dirt
	? expect.1
	? expect.2
	? output.1
	? output.2
	? serialized_status.dat
	? trace.2
	? untracked/
	? untracked_1.txt
	EOF

	sleep 1 &&
	touch .git/index &&
	GIT_TRACE_DESERIALIZE=1 git status --porcelain=v2 --deserialize=serialized_status.dat --deserialize-wait=2 >output.2 2>trace.2 &&
	test_cmp expect.2 output.2 &&
	grep "wait polled=2 result=1" trace.2 >trace.2g
'

test_expect_success 'merge conflicts' '

	# create a merge conflict.

	git init conflicts &&
	echo x >conflicts/x.txt &&
	git -C conflicts add x.txt &&
	git -C conflicts commit -m x &&
	git -C conflicts branch a &&
	git -C conflicts branch b &&
	git -C conflicts checkout a &&
	echo y >conflicts/x.txt &&
	git -C conflicts add x.txt &&
	git -C conflicts commit -m a &&
	git -C conflicts checkout b &&
	echo z >conflicts/x.txt &&
	git -C conflicts add x.txt &&
	git -C conflicts commit -m b &&
	test_must_fail git -C conflicts merge --no-commit a &&

	# verify that regular status correctly identifies it
	# in each format.

	cat >expect.v2 <<EOF &&
u UU N... 100644 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb b68025345d5301abad4d9ec9166f455243a0d746 975fbec8256d3e8a3797e7a3611380f27c49f4ac x.txt
EOF
	git -C conflicts status --porcelain=v2 >observed.v2 &&
	test_cmp expect.v2 observed.v2 &&

	cat >expect.long <<EOF &&
On branch b
You have unmerged paths.
  (fix conflicts and run "git commit")
  (use "git merge --abort" to abort the merge)

Unmerged paths:
  (use "git add <file>..." to mark resolution)
	both modified:   x.txt

no changes added to commit (use "git add" and/or "git commit -a")
EOF
	git -C conflicts status --long >observed.long &&
	test_cmp expect.long observed.long &&

	cat >expect.short <<EOF &&
UU x.txt
EOF
	git -C conflicts status --short >observed.short &&
	test_cmp expect.short observed.short &&

	# save status data in serialized cache.

	git -C conflicts status --serialize >serialized &&

	# make some dirt in the worktree so we can tell whether subsequent
	# status commands used the cached data or did a fresh status.

	echo dirt >conflicts/dirt.txt &&

	# run status using the cached data.

	git -C conflicts status --long --deserialize=../serialized >observed.long &&
	test_cmp expect.long observed.long &&

	git -C conflicts status --short --deserialize=../serialized >observed.short &&
	test_cmp expect.short observed.short &&

	# currently, the cached data does not have enough information about
	# merge conflicts for porcelain V2 format.  (And V2 format looks at
	# the index to get that data, but the whole point of the serialization
	# is to avoid reading the index unnecessarily.)  So V2 always rejects
	# the cached data when there is an unresolved conflict.

	cat >expect.v2.dirty <<EOF &&
u UU N... 100644 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb b68025345d5301abad4d9ec9166f455243a0d746 975fbec8256d3e8a3797e7a3611380f27c49f4ac x.txt
? dirt.txt
EOF
	git -C conflicts status --porcelain=v2 --deserialize=../serialized >observed.v2 &&
	test_cmp expect.v2.dirty observed.v2

'

test_expect_success 'renames' '
	git init rename_test &&
	echo OLDNAME >rename_test/OLDNAME &&
	git -C rename_test add OLDNAME &&
	git -C rename_test commit -m OLDNAME &&
	git -C rename_test mv OLDNAME NEWNAME &&
	git -C rename_test status --serialize=renamed.dat >output.1 &&
	echo DIRT >rename_test/DIRT &&
	git -C rename_test status --deserialize=renamed.dat >output.2 &&
	test_i18ncmp output.1 output.2
'

test_expect_success 'hint message when cached with u=complete' '
	git init hint &&
	echo xxx >hint/xxx &&
	git -C hint add xxx &&
	git -C hint commit -m xxx &&

	cat >expect.clean <<EOF &&
On branch master
nothing to commit, working tree clean
EOF

	cat >expect.use_u <<EOF &&
On branch master
nothing to commit (use -u to show untracked files)
EOF

	# Capture long format output from "no", "normal", and "all"
	# (without using status cache) and verify it matches expected
	# output.

	git -C hint status --untracked-files=normal >hint.output_normal &&
	test_i18ncmp expect.clean hint.output_normal &&

	git -C hint status --untracked-files=all >hint.output_all &&
	test_i18ncmp expect.clean hint.output_all &&

	git -C hint status --untracked-files=no >hint.output_no &&
	test_i18ncmp expect.use_u hint.output_no &&

	# Create long format output for "complete" and create status cache.

	git -C hint status --untracked-files=complete --ignored=matching --serialize=../hint.dat >hint.output_complete &&
	test_i18ncmp expect.clean hint.output_complete &&

	# Capture long format output using the status cache and verify
	# that the output matches the non-cached version.  There are 2
	# ways to specify untracked-files, so do them both.

	git -C hint status --deserialize=../hint.dat -unormal >hint.d1_normal &&
	test_i18ncmp expect.clean hint.d1_normal &&
	git -C hint -c status.showuntrackedfiles=normal status --deserialize=../hint.dat >hint.d2_normal &&
	test_i18ncmp expect.clean hint.d2_normal &&

	git -C hint status --deserialize=../hint.dat -uall >hint.d1_all &&
	test_i18ncmp expect.clean hint.d1_all &&
	git -C hint -c status.showuntrackedfiles=all status --deserialize=../hint.dat >hint.d2_all &&
	test_i18ncmp expect.clean hint.d2_all &&

	git -C hint status --deserialize=../hint.dat -uno >hint.d1_no &&
	test_i18ncmp expect.use_u hint.d1_no &&
	git -C hint -c status.showuntrackedfiles=no status --deserialize=../hint.dat >hint.d2_no &&
	test_i18ncmp expect.use_u hint.d2_no

'

test_expect_success 'ensure deserialize -v does not crash' '

	git init verbose_test &&
	touch verbose_test/a &&
	touch verbose_test/b &&
	touch verbose_test/c &&
	git -C verbose_test add a b c &&
	git -C verbose_test commit -m abc &&

	echo green >>verbose_test/a &&
	git -C verbose_test add a &&
	echo red_1 >>verbose_test/b &&
	echo red_2 >verbose_test/dirt &&

	git -C verbose_test status    >output.ref &&
	git -C verbose_test status -v >output.ref_v &&

	git -C verbose_test --no-optional-locks status --serialize=../verbose_test.dat      >output.ser.long &&
	git -C verbose_test --no-optional-locks status --serialize=../verbose_test.dat_v -v >output.ser.long_v &&

	# Verify that serialization does not affect the status output itself.
	test_i18ncmp output.ref   output.ser.long &&
	test_i18ncmp output.ref_v output.ser.long_v &&

	GIT_TRACE2_PERF="$(pwd)"/verbose_test.log \
	git -C verbose_test status --deserialize=../verbose_test.dat >output.des.long &&

	# Verify that normal deserialize was actually used and produces the same result.
	test_i18ncmp output.ser.long output.des.long &&
	grep -q "deserialize/result:ok" verbose_test.log &&

	GIT_TRACE2_PERF="$(pwd)"/verbose_test.log_v \
	git -C verbose_test status --deserialize=../verbose_test.dat_v -v >output.des.long_v &&

	# Verify that vebose mode produces the same result because verbose was rejected.
	test_i18ncmp output.ser.long_v output.des.long_v &&
	grep -q "deserialize/reject:args/verbose" verbose_test.log_v
'

test_done
