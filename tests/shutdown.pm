use base "basetest";
use strict;
use testapi;

sub run {
    # shutdown before uploading disk image
    select_console('root-console');
    script_run("poweroff", 0);
    assert_shutdown 300;
}

# this is not 'fatal' or 'important' as all wiki test cases are passed
# even if shutdown fails. we should have a separate test for shutdown/
# logout/reboot stuff, might need some refactoring.
sub test_flags {
    return { 'norollback' => 1, 'ignore_failure' => 1 };
}

1;

# vim: set sw=4 et:
