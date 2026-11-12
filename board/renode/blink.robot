*** Comments ***
Runs board_blink on an emulated Raspberry Pi Pico (RP2040) in Renode 1.16.1.
RP2040_MODEL must be the path of a checkout of github.com/matgla/Renode_RP2040.
That RP2040 model is a community project. It does not model all peripherals.

*** Settings ***
Suite Setup       Setup
Suite Teardown    Teardown
Test Teardown     Test Teardown
Test Timeout      120 seconds

*** Variables ***
${MODEL}          %{RP2040_MODEL}
${ELF}            ${CURDIR}/../bin/board_blink

*** Test Cases ***
Board_Blink Toggles The LED Every 500 ms
    Execute Command    $machine_name="pico"
    Execute Command    include @${MODEL}/cores/initialize_peripherals_source.resc
    Execute Command    machine LoadPlatformDescription @${MODEL}/boards/raspberry_pico.repl
    Execute Command    sysbus LoadELF @${MODEL}/bootroms/rp2040/b2.elf
    Execute Command    emulation SetGlobalQuantum "0.0001"
    Execute Command    sysbus LoadELF @${ELF}
    Execute Command    sysbus.cpu0 VectorTableOffset 0x00000000
    Execute Command    sysbus.cpu1 VectorTableOffset 0x00000000
    Create LED Tester    sysbus.gpio.led
    Assert LED Is Blinking    testDuration=3    onDuration=0.5    offDuration=0.5    tolerance=0.05
