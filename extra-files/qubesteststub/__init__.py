import asyncio

import qubes.ext
import qubes.vm.qubesvm
import xen.lowlevel.xc

class DefaultPV(qubes.ext.Extension):

    @qubes.ext.handler('domain-pre-start')
    def on_domain_pre_start(self, vm, event, **kwargs):
        if len(vm.devices['pci'].persistent()):
            # IOMMU missing
            if 'hvm_directio' not in self.physinfo['virt_caps'] and vm.virt_mode != 'pv':
                vm.virt_mode = 'pv'
            # disable e820_host, otherwise guest crashes when host booted with OVMF
            vm.features['pci-e820-host'] = False

    def __init__(self):
        super().__init__()
        x = xen.lowlevel.xc.xc()
        self.physinfo = x.physinfo()
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
