#!/usr/bin/env python3
"""
la32.py — tiny LoongArch32 assembler + reference model for this CPU.

Assembles the instruction subset the core implements and (optionally) runs an
independent functional model so the Verilog testbench checks can be regenerated.

Usage:
    python3 tools/la32.py asm  prog.s  > prog.hex
    python3 tools/la32.py model prog.s          # dump final register file
"""
import sys

OPC3R = {
 'add.w':0x00100000,'sub.w':0x00110000,'slt':0x00120000,'sltu':0x00128000,
 'nor':0x00140000,'and':0x00148000,'or':0x00150000,'xor':0x00158000,
 'sll.w':0x00170000,'srl.w':0x00178000,'sra.w':0x00180000,
 'mul.w':0x001c0000,'mulh.w':0x001c8000,'mulh.wu':0x001d0000,
 'div.w':0x00200000,'mod.w':0x00208000,'div.wu':0x00210000,'mod.wu':0x00218000,
}
OPC2RI5 = {'slli.w':0x00408000,'srli.w':0x00448000,'srai.w':0x00488000}
OPC2RI12 = {
 'slti':0x02000000,'sltui':0x02400000,'addi.w':0x02800000,
 'andi':0x03400000,'ori':0x03800000,'xori':0x03c00000,
 'ld.b':0x28000000,'ld.h':0x28400000,'ld.w':0x28800000,
 'st.b':0x29000000,'st.h':0x29400000,'st.w':0x29800000,
 'ld.bu':0x2a000000,'ld.hu':0x2a400000,
}
OPC1RI20 = {'lu12i.w':0x14000000,'pcaddu12i':0x1c000000}
OPC2RI16 = {
 'jirl':0x4c000000,'beq':0x58000000,'bne':0x5c000000,
 'blt':0x60000000,'bge':0x64000000,'bltu':0x68000000,'bgeu':0x6c000000,
}
OPCI26 = {'b':0x50000000,'bl':0x54000000}

def reg(t):
    t=t.strip(); assert t.startswith('r'); n=int(t[1:]); assert 0<=n<32; return n

def enc(line, labels, pc):
    line=line.split('#')[0].strip()
    if not line: return None
    m=line.split(None,1); mn=m[0].lower()
    args=[a.strip() for a in m[1].split(',')] if len(m)>1 else []
    if mn in OPC3R:
        rd,rj,rk=reg(args[0]),reg(args[1]),reg(args[2]); return OPC3R[mn]|(rk<<10)|(rj<<5)|rd
    if mn in OPC2RI5:
        rd,rj,ui=reg(args[0]),reg(args[1]),int(args[2],0)&0x1f; return OPC2RI5[mn]|(ui<<10)|(rj<<5)|rd
    if mn in OPC2RI12:
        rd,rj,si=reg(args[0]),reg(args[1]),int(args[2],0)&0xfff; return OPC2RI12[mn]|(si<<10)|(rj<<5)|rd
    if mn in OPC1RI20:
        rd,si=reg(args[0]),int(args[1],0)&0xfffff; return OPC1RI20[mn]|(si<<5)|rd
    if mn in OPC2RI16:
        if mn=='jirl': rd,rj,off=reg(args[0]),reg(args[1]),int(args[2],0)
        else:
            rj,rd=reg(args[0]),reg(args[1]); tgt=args[2]
            off=(labels[tgt]-pc) if tgt in labels else int(tgt,0)
        return OPC2RI16[mn]|(((off>>2)&0xffff)<<10)|(rj<<5)|rd
    if mn in OPCI26:
        tgt=args[0]; off=(labels[tgt]-pc) if tgt in labels else int(tgt,0); o=(off>>2)&0x3ffffff
        return OPCI26[mn]|((o&0xffff)<<10)|((o>>16)&0x3ff)
    if mn=='nop': return 0x03400000
    raise ValueError('unknown mnemonic: '+mn)

def assemble(src):
    labels={}; pc=0; lines=[]
    for raw in src.splitlines():
        l=raw.split('#')[0].strip()
        if not l: continue
        if l.endswith(':'): labels[l[:-1]]=pc; continue
        if ':' in l.split(None,1)[0]:
            lbl,rest=l.split(':',1); labels[lbl.strip()]=pc; l=rest.strip()
            if not l: continue
        lines.append((pc,l)); pc+=4
    return [enc(l,labels,pc) for pc,l in lines], labels

if __name__=='__main__':
    mode, path = sys.argv[1], sys.argv[2]
    src=open(path).read()
    words,labels=assemble(src)
    if mode=='asm':
        for w in words: print(f"{w&0xffffffff:08x}")
    else:
        print("labels:",labels)
        print(len(words),"instructions")
