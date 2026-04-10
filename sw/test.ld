ENTRY(_start)

SECTIONS
{
    . = 0x00000400;
    .text : { *(.text) }
}
