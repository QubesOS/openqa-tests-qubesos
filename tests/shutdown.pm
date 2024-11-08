use base "basetest";
use strict;
use testapi;

sub run {
    select_console('root-console');
    # make upload as small as possible
    script_run("fstrim -v /", timeout => 180);
    if (get_var("STORE_HDD_1") || get_var("PUBLISH_HDD_1")) {
        # shutdown before uploading disk image
        script_run("poweroff", 0);
        assert_shutdown 300;
    } elsif (check_var("BACKEND", "generalhw")) {
        # otherwise just sync and remount /boot (clears the orphan present
        # flag) if running non-virtualized
        script_run("! mountpoint -q /boot/efi || mount -o ro,remount /boot/efi");
        script_run("! mountpoint -q /boot || mount -o ro,remount /boot");
        script_run("sync");
    }

}

# this is not 'fatal' or 'important' as all wiki test cases are passed
# even if shutdown fails. we should have a separate test for shutdown/
# logout/reboot stuff, might need some refactoring.
sub test_flags {
    return { 'norollback' => 1, 'ignore_failure' => 1 };
}

1;

# vim: set sw=4 et:
