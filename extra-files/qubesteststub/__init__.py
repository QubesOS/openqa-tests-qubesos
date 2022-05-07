import asyncio
import subprocess
import pathlib

import qubes.ext
import qubes.vm.qubesvm
import xen.lowlevel.xc
from qubes.devices import DeviceAssignment

class DefaultPV(qubes.ext.Extension):

    @qubes.ext.handler('domain-pre-start')
    @asyncio.coroutine
    def on_domain_pre_start(self, vm, event, **kwargs):
        # on Xen 4.13 PCI passthrough on PV requires IOMMU too
        pv_passthrough_available = (self.xeninfo['xen_minor'] < 13 or 
            'qubes.enable_insecure_pv_passthrough' in self.dom0_cmdline)
        if 'hvm_directio' not in self.physinfo['virt_caps'] and not pv_passthrough_available:
            if vm.name in ('sys-net', 'sys-usb'):
                for ass in list(vm.devices['pci'].assignments()):
                    yield from vm.devices['pci'].detach(ass)
        elif 'hvm_directio' in self.physinfo['virt_caps'] or pv_passthrough_available:
            # IOMMU is available, (re)attach devices
            if vm.name == 'sys-net':
                missing = set(self.netdevs)
            elif vm.name == 'sys-usb':
                missing = set(self.usbdevs)
            else:
                missing = set()

            for dev in vm.devices['pci'].persistent():
                missing.discard(dev.ident.replace('_', ':'))
            for dev in missing:
                ass = DeviceAssignment(vm.app.domains[0], dev.replace(':', '_'),
                        options={'no-strict-reset': 'True'},
                        persistent=True)
                yield from vm.devices['pci'].attach(ass)

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
            for dev in self.netdevs:
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/pciback/unbind'.format(dev), shell=True)
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/e1000e/bind'.format(dev), shell=True)
            # wait for udev and co
            yield from asyncio.sleep(1)
            subprocess.call('udevadm settle', shell=True)
            yield from asyncio.sleep(1)
            iface = subprocess.check_output('ls /sys/class/net|grep ^en', shell=True).decode()
            iface = iface.strip()
            subprocess.call('brctl addbr xenbr0', shell=True)
            subprocess.call('brctl addif xenbr0 {}'.format(iface), shell=True)
            subprocess.call('ip l s {} up'.format(iface), shell=True)
            subprocess.call('ip l s xenbr0 up', shell=True)
            subprocess.call('xl network-attach sys-net bridge=xenbr0', shell=True)
        if vm.name == 'sys-usb' and not len(vm.devices['pci'].persistent()):
            for dev in self.usbdevs:
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/pciback/unbind'.format(dev), shell=True)
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/ehci-pci/bind'.format(dev), shell=True)

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

        self.netdevs = []
        self.usbdevs = []
        lspci = subprocess.check_output(['lspci', '-n']).decode()
        for line in lspci.splitlines():
            bdf = line.split()[0]
            if '0200:' in line:
                self.netdevs.append(bdf)
            if '0c03:' in line:
                self.usbdevs.append(bdf)

        qubes.vm.qubesvm.QubesVM.qrexec_timeout._default = 90
        qubes.vm.qubesvm.QubesVM.qrexec_timeout._default_function = None
        if 'xen_scrub_pages' not in qubes.config.defaults['kernelopts']:
            qubes.config.defaults['kernelopts'] += ' xen_scrub_pages=0'
            qubes.config.defaults['kernelopts_pcidevs'] += ' xen_scrub_pages=0'
        if 'journald' not in qubes.config.defaults['kernelopts']:
            qubes.config.defaults['kernelopts'] += ' systemd.journald.forward_to_console=1'
            qubes.config.defaults['kernelopts_pcidevs'] += ' systemd.journald.forward_to_console=1'

        self.dom0_cmdline = pathlib.Path('/proc/cmdline').read_bytes().decode()

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
