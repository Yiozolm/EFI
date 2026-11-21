// Re-enumerate the Intel AX210 Bluetooth USB device (8087:0032) so IntelBluetoothFirmware probes it again.
// Build: clang -O2 -o reenum reenum.c -framework IOKit -framework CoreFoundation
// Run:   sudo ./reenum
#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

int main(void) {
    CFMutableDictionaryRef m = IOServiceMatching("IOUSBHostDevice");
    int vid = 0x8087, pid = 0x0032;
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vid), p = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    CFDictionarySetValue(m, CFSTR("idVendor"), v);
    CFDictionarySetValue(m, CFSTR("idProduct"), p);
    io_service_t dev = IOServiceGetMatchingService(kIOMainPortDefault, m);
    if (!dev) { fprintf(stderr, "8087:0032 not found\n"); return 1; }

    IOCFPlugInInterface **plug = NULL; SInt32 score;
    kern_return_t kr = IOCreatePlugInInterfaceForService(dev, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score);
    if (kr || !plug) { fprintf(stderr, "plugin failed 0x%x\n", kr); return 1; }
    IOUSBDeviceInterface650 **d = NULL;
    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID650), (LPVOID *)&d);
    (*plug)->Release(plug);
    if (!d) { fprintf(stderr, "QueryInterface failed\n"); return 1; }

    kr = (*d)->USBDeviceOpenSeize(d);
    printf("open(seize): 0x%x\n", kr);
    kr = (*d)->USBDeviceReEnumerate(d, 0);
    printf("re-enumerate: 0x%x\n", kr);
    (*d)->USBDeviceClose(d);
    (*d)->Release(d);
    IOObjectRelease(dev);
    return kr ? 1 : 0;
}
