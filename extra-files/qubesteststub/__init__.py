import asyncio
import subprocess

import qubes.ext
import qubes.vm.qubesvm
import xen.lowlevel.xc

class DefaultPV(qubes.ext.Extension):

    @qubes.ext.handler('domain-pre-start')
    def on_domain_pre_start(self, vm, event, **kwargs):
        # on Xen 4.13 PCI passthrough on PV requires IOMMU too
        if self.xeninfo['xen_minor'] >= 13:
            if vm.name in ('sys-net', 'sys-usb'):
                for ass in list(vm.devices['pci'].assignments()):
                    yield from vm.devices['pci'].detach(ass)

        if len(vm.devices['pci'].persistent()):
            # IOMMU missing
            if 'hvm_directio' not in self.physinfo['virt_caps'] and vm.virt_mode != 'pv':
                vm.virt_mode = 'pv'
            # disable e820_host, otherwise guest crashes when host booted with OVMF
            vm.features['pci-e820-host'] = False

    @qubes.ext.handler('domain-start')
    @asyncio.coroutine
    def on_domain_start(self, vm, event, **kwargs):
        if vm.name == 'sys-net' and not len(vm.devices['pci'].persistent()):
            subprocess.call('echo 0000:00:04.0 > /sys/bus/pci/drivers/pciback/unbind', shell=True)
            subprocess.call('echo 0000:00:04.0 > /sys/bus/pci/drivers/e1000e/bind', shell=True)
            # wait for udev and co
            yield from asyncio.sleep(1)
            subprocess.call('udevadm settle', shell=True)
            subprocess.call('brctl addbr xenbr0', shell=True)
            subprocess.call('brctl addif xenbr0 ens4', shell=True)
            subprocess.call('ip l s ens4 up', shell=True)
            subprocess.call('ip l s xenbr0 up', shell=True)
            subprocess.call('xl network-attach sys-net bridge=xenbr0', shell=True)
        if vm.name == 'sys-usb' and not len(vm.devices['pci'].persistent()):
            subprocess.call('echo 0000:00:05.0 > /sys/bus/pci/drivers/pciback/unbind', shell=True)
            subprocess.call('echo 0000:00:05.0 > /sys/bus/pci/drivers/ehci-pci/bind', shell=True)

    def __init__(self):
        super().__init__()
        x = xen.lowlevel.xc.xc()
        self.physinfo = x.physinfo()
        self.xeninfo = x.xeninfo()
        del x
        if 'hvm' not in self.physinfo['virt_caps']:
            qubes.vm.qubesvm.QubesVM.virt_mode._default = 'pv'
            qubes.vm.qubesvm.QubesVM.virt_mode._default_function = None
            qubes.vm.qubesvm.QubesVM.virt_mode._setter = lambda _self, _prop, _value: 'pv'
        else:
            # nested SVM has problems with SMP guests...
            qubes.vm.qubesvm.QubesVM.vcpus._default_function = (lambda _self:
                2 if _self.kernel and _self.kernel.startswith('4')
                      and _self.kernel.split('.') >= ['4', '15'] else 1)

        qubes.vm.qubesvm.QubesVM.qrexec_timeout._default = 90
        qubes.vm.qubesvm.QubesVM.qrexec_timeout._default_function = None
        if 'xen_scrub_pages' not in qubes.config.defaults['kernelopts']:
            qubes.config.defaults['kernelopts'] += ' xen_scrub_pages=0'
            qubes.config.defaults['kernelopts_pcidevs'] += ' xen_scrub_pages=0'
        if 'journald' not in qubes.config.defaults['kernelopts']:
            qubes.config.defaults['kernelopts'] += ' systemd.journald.forward_to_console=1'
            qubes.config.defaults['kernelopts_pcidevs'] += ' systemd.journald.forward_to_console=1'

    @qubes.ext.handler('features-request')
    @asyncio.coroutine
    def on_features_request(self, vm, event, untrusted_features):
        if vm.klass != 'TemplateVM':
            return
        if not vm.features.get('fixups-installed', False):
            # nested virtualization confuses systemd
            dropin = '/etc/systemd/system/xendriverdomain.service.d'
            yield from vm.run_for_stdio('mkdir -p {dropin} && echo -e "[Unit]\\nConditionVirtualization=" > {dropin}/30_openqa.conf'.format(dropin=dropin), user='root')
            vm.features['fixups-installed'] = True

    @qubes.ext.handler('domain-start-failed')
    def on_start_failed(self, vm, event, **kwargs):
        import time
        print('VM {} start failed at {}'.format(vm.name, time.strftime('%F %T')))
