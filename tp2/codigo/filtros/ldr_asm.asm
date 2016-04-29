global ldr_asm

section .data
DEFAULT REL

%define pixelSize 4

; En memoria: BGRA
; En registros: ARGB
; a3|r3|g3|b3|a2|r2|g2|b2|a1|r1|g1|b1|a0|r0|g0|b0 -> a3|a2|a1|a0|r3|g3|b3|r2|g2|b2|r1|g1|b1|r0|g0|b0
; Las siguientes dos mascaras me permiten hacer lo mismo que un unpck pero ademas limpio canales alpha dado que no asumo que sean 0 por default.
punpcklbwAndCleanAlpha: DB 0x00, 0x88, 0x01, 0x89, 0x02, 0x8A, 0x83, 0x8B, 0x04, 0x8C, 0x05, 0x8D, 0x06, 0x8E, 0x87, 0x8F 
punpckhbwAndCleanAlpha: DB 0x08, 0x81, 0x09, 0x82, 0x0A, 0x83, 0x8B, 0x84, 0x0C, 0x85, 0x0D, 0x86, 0x0E, 0x87, 0x8F, 0x88 
saveOnePixelShifter: DB 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x00
maxValue: DD 0x004A6A4B ; check this 4876875

section .text
;void ldr_asm    (
	;unsigned char *src, rdi
	;unsigned char *dst, rsi
	;int cols, edx
	;int filas, ecx
	;int src_row_size, r8d -> no se usa
	;int dst_row_size, r9d -> no se usa
	;int alpha) rsp-8

	; r8 posicion actual
	; r9 contador columnas

ldr_asm:
	push rbp
	mov rbp, rsp
	push rbx
	push r12
	push r13
	push r14
	push r15

	xor rbx, rbx
	xor r12, r12
	xor r13, r13
	xor r14, r14
	xor r15, r15
	
	mov ebx, [rbp+16] ; alpha
	mov r13d, [maxValue] ; MAX

	cmp ebx, -255
	jl .sinCambios
	cmp ebx, 255
	jg .sinCambios
	cmp edx, 4
	jle .sinCambios ; si tengo menos de cuatro filas terminar.
	cmp ecx, 4
	jle .sinCambios ; si tengo menos que cuatro columnas terminar.

	xor r8, r8 ; posicion actual
	xor r9, r9 ; j = 0
	mov r8d, edx ; r8 = cols

	mov r15d, edx ; r15d = cols
	xor rdx, rdx
	mov r14d, ecx ; r14d = filas.
	sub r14d, 2 ; filas-2
	xor rax, rax ; limpio para usar en multiplicacion.
	mov eax, r15d
	mul r14d ; edx:eax = r15d*r14d = cols*(filas-2).
	mov ecx, edx
	shl rdx, 32
	mov ecx, eax ; ecx = r15d*r14d = cols*(filas-2). contador loop.

	xor r11, r11
	mov r11d, r15d
	sub r11d, 2 ; cols-2 = colsToProccess

	shl r8, 1 ; r8*2 = i = 2 - j = 0

	movdqu xmm6, [punpcklbwAndCleanAlpha]
	movdqu xmm7, [punpckhbwAndCleanAlpha]
	movdqu xmm8, [saveOnePixelShifter]
	movdqu xmm15, xmm8 ; 0|FF|FF|FF|0|0|0|0|0|0|0|0|0|0|0|0
    psrldq xmm15, 12 ; 0|0|0|0|0|0|0|0|0|0|0|0|0|FF|FF|FF
    movdqu xmm4, xmm8
    psrldq xmm4, 14
    pslldq xmm4, 3 ; 0|0|0|0|0|0|0|0|0|0|0|0|FF|0|0|0

	pxor xmm11, xmm11

.ciclo: ; while(r8 < rcx) == (actual < total) 
; if(j > 1)
	cmp r9, 2
	jl .menorAColDos
	; estoy en rango.
	mov r12, r8 ; posicion actual
	sub r12, r15
	sub r12, r15 ; posicion actual - dos filas
	sub r12, 2 ; me corro -2 posiciones
	xor r10, r10 ; cuento hasta 5

	pxor xmm0, xmm0

.cincoHorizontal:

	; 16  12   8   4   0
	; Li4|Li3|Li2|Li1|Li0
    ;VERSION STANDARD: Con 2 accesos - acceso extra paa el pixel 5
    movdqu xmm13, [rdi + r12*pixelSize] ; Li3|Li2|Li1|Li0

	movdqu xmm9, xmm13
	pshufb xmm9, xmm6 ; 0|0|0|r1|0|g1|0|b1|0|0|0|r0|0|g0|0|b0
	phaddw xmm9, xmm11 ; 0|0|0|0|0+r1|g1+b1|0+r0|g0+b0 -- maximo por w = 510 in []
	pshufb xmm13, xmm7 ; 0|0|0|r3|0|g3|0|b3|0|0|0|r2|0|g2|0|b2
    phaddw xmm13, xmm11 ; 0|0|0|0|r3|g3+b3|r2|g2+b2 -- maximo por w = 510 in []
    punpcklwd xmm9, xmm11 ; r1|g1+b1|r0|g0+b0
    punpcklwd xmm13, xmm11 ; r3|g3+b3|r2|g2+b2
    paddd xmm13, xmm9 ; r3+r1|g3+b3+g1+b1|r2+r0|g2+b2+g0+b0 -- maximo por dw = 1020 in []
    movdqu xmm9, xmm13
    psrldq xmm9, 8 ; 0|0|r3+r1|g3+b3+g1+b1
    paddd xmm13, xmm9 ; r3+r1|g3+b3+g1+b1|r2+r0+r3+r1|g2+b2+g0+b0+g3+b3+g1+b1  -- maximo por dw = 2040 in []
    pslldq xmm13, 8 ; r2+r0+r3+r1|g2+b2+g0+b0+g3+b3+g1+b1|0|0
    psrldq xmm13, 8 ; 0|0|r2+r0+r3+r1|g2+b2+g0+b0+g3+b3+g1+b1
	movd xmm9, [rdi + r12*pixelSize + 16] ; 0|0|0|0|0|0|0|0|0|0|0|0|a4|r4|g4|b4

	pslldq xmm9, 12 ; a4|r4|g4|b4|0|0|0|0|0|0|0|0|0|0|0|0
	pand xmm9, xmm8 ; 0|r4|g4|b4|0|0|0|0|0|0|0|0|0|0|0|0
	pshufb xmm9, xmm7 ; 0|0|0|r4|0|g4|0|b4|0|0|0|0|0|0|0|0
	phaddw xmm9, xmm11 ; 0|0|0|0|r4|g4+b4|0|0 -- maximo por w = 510 in []
	punpcklwd xmm9, xmm11 ; 0|r4|0|g4+b4|0|0|0|0
	psrldq xmm9, 8 ; 0|0|r4|g4+b4
	paddd xmm13, xmm9 ; 0|0|r2+r0+r3+r1+r4|g2+b2+g0+b0+g3+b3+g1+b1+g4+b4 -- maximo por dw = 2550 in []
	movdqu xmm9, xmm13
	psrldq xmm9, 4 ; 0|0|0|r2+r0+r3+r1+r4
	paddd xmm13, xmm9 ; 0|0|r2+r0+r3+r1+r4|g2+b2+g0+b0+g3+b3+g1+b1+g4+b4+r2+r0+r3+r1+r4 -- maximo por dw = 3825 in []
	pslldq xmm13, 12 ; g2+b2+g0+b0+g3+b3+g1+b1+g4+b4+r2+r0+r3+r1+r4|0|0|0
	psrldq xmm13, 12 ; 0|0|0|g2+b2+g0+b0+g3+b3+g1+b1+g4+b4+r2+r0+r3+r1+r4
	paddd xmm0, xmm13 ; suma de la i fila para el pixel ij.

	add r12, r15
	inc r10
	cmp r10, 5
	jl .cincoHorizontal

	pxor xmm13, xmm13
	movd xmm13, ebx
	movdqu xmm12, xmm13 ; 0|0|0|alpha
	pslldq xmm12, 4 ; 0|0|alpha|0
	por xmm12, xmm13 ; 0|0|alpha|alpha
	pslldq xmm12, 4 ; 0|alpha|alpha|0
	por xmm12, xmm13 ; 0|alpha|alpha|alpha

	pxor xmm14, xmm14
	movd xmm14, r13d
	movdqu xmm13, xmm14 ; 0|0|0|max
	pslldq xmm13, 4 ; 0|0|max|0
	por xmm13, xmm14 ; 0|0|max|max
	pslldq xmm13, 4 ; 0|max|max|0
	por xmm13, xmm14 ; 0|max|max|max
	pslldq xmm13, 4 ; max|max|max|0
	por xmm13, xmm14 ; max|max|max|max

	movdqu xmm5, xmm0
	pslldq xmm5, 4
	por xmm5, xmm0
	pslldq xmm5, 4
	por xmm5, xmm0
	pxor xmm14, xmm14
	movd xmm14, [rdi + r8*pixelSize] ; 0|0|0|0|0|0|0|0|0|0|0|0|a|r|g|b <- get pixel ij
	movdqu xmm0, xmm14 ; 0|0|0|0|0|0|0|0|0|0|0|0|a|r|g|b
	pand xmm0, xmm15 ; 0|0|0|0|0|0|0|0|0|0|0|0|0|r|g|b
	punpcklbw xmm0, xmm11 ; 0|0|0|0|0|r|g|b
	punpcklwd xmm0, xmm11 ; 0|r|g|b
	pmulld xmm5, xmm0 ; 0|sumargb*r|sumargb*g|sumargb*b == 0|sumargb*r|sumargb*g|sumargb*b -- maximo posible por dword 75*255*255 = 4876875 in  [−2,147,483,648 to 2,147,483,647]
	pmulld xmm5, xmm12 ; 0|alpha*sumargb*r|alpha*sumargb*g|alpha*sumargb*b <- puede cambiar el signo segun alpha. -- maximo posible por dword 75*255*255*255 or 75*255*255*-255 = +-1,243,603,125 in  [−2,147,483,648 to 2,147,483,647]
    cvtdq2ps xmm5, xmm5 ; 0|fp(alpha*sumargb*r)|fp(alpha*sumargb*g)|fp(alpha*sumargb*b)
	cvtdq2ps xmm13, xmm13 ; fp(max)|fp(max)|fp(max)|fp(max)
	divps xmm5, xmm13 ; 0|(alpha*sumargb*r)/max|(alpha*sumargb*g)/max|(alpha*sumargb*b)/max
	cvtdq2ps xmm0, xmm0 ; 0|fp(r)|fp(g)|fp(b)
	addps xmm5, xmm0 ; 0|r+(alpha*sumargb*r)/max|g+(alpha*sumargb*g)/max|b+(alpha*sumargb*b)/max
	cvttps2dq xmm5, xmm5 ; cast to dw signed 
	packusdw xmm5, xmm11 ; 0|0|0|0|0|r+(alpha*sumargb*r)/g+max|(alpha*sumargb*g)/b+max|(alpha*sumargb*b)/max
	packuswb xmm5, xmm11 ; 0|0|0|0|0|0|0|0|0|0|0|0|0|r+(alpha*sumargb*r)/g+max|(alpha*sumargb*g)/b+max|(alpha*sumargb*b)/max <- tengo los canales calculados saturados a byte.
	pand xmm14, xmm4 ; 0|0|0|0|0|0|0|0|0|0|0|0|a|0|0|0
	por xmm14, xmm5 ; 0|0|0|0|0|0|0|0|0|0|0|0|a|r+(alpha*sumargb*r)/max|g+(alpha*sumargb*g)/max|b+(alpha*sumargb*b)/max

    movd [rsi + r8*pixelSize], xmm14

	inc r9
	inc r8
	cmp r9, r11
	je .igualAColsToProccess ; mayor igual a colsToProccess
	jmp .seguir

.menorAColDos:
	pxor xmm10, xmm10
	movd xmm10, [rdi + r8*pixelSize]
	movd [rsi + r8*pixelSize], xmm10
	inc r8
	inc r9
	pxor xmm10, xmm10
	movd xmm10, [rdi + r8*pixelSize]
	movd [rsi + r8*pixelSize], xmm10
	inc r8
	inc r9
	jmp .seguir

.igualAColsToProccess:
	pxor xmm10, xmm10
	movd xmm10, [rdi + r8*pixelSize]
	movd [rsi + r8*pixelSize], xmm10
	inc r8
	movd xmm10, [rdi + r8*pixelSize]
	movd [rsi + r8*pixelSize], xmm10
    inc r8

	xor r9, r9 ; reinicio contador columna actual.

.seguir:
	movdqu xmm8, xmm15 ; 0|0|0|0|0|0|0|0|0|0|0|0|0|FF|FF|FF
	pslldq xmm8, 12 ; 0|FF|FF|FF|0|0|0|0|0|0|0|0|0|0|0|0
	cmp r8, rcx
	jl .ciclo

.sinCambios:
	xor r8, r8
	xor r9, r9
	mov r9, rcx ; cols*(filas-2)
	shl r15, 1 ; cols*2
.devolver:
	movdqu xmm10, [rdi + r8*pixelSize]
	movdqu xmm11, [rdi + r9*pixelSize]
	movdqu [rsi + r8*pixelSize], xmm10
	movdqu [rsi + r9*pixelSize], xmm11
	add r8, pixelSize
	add r9, pixelSize
	cmp r8, r15 ; cuando complete las dos primeras, tambien completo las dos ultimas.
	jl .devolver

; DONE!!.

.salir:
	pop r15
	pop r14
	pop r13
	pop r12
	pop rbx
	pop rbp
	ret
