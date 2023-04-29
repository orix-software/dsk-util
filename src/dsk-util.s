.feature labels_without_colons
.feature string_escapes
.macpack longbranch

;----------------------------------------------------------------------
;			cc65 includes
;----------------------------------------------------------------------
.include "telestrat.inc"
.include "fcntl.inc"
.include "ch376.inc"

;----------------------------------------------------------------------
;			Orix SDK includes
;----------------------------------------------------------------------
.include "SDK.mac"
.include "SDK.inc"
.include "types.mac"
.include "errors.inc"
.include "ch376.inc"

;----------------------------------------------------------------------
;				Imports
;----------------------------------------------------------------------
; From debug
.import PrintHexByte
.import PrintRegs

; From sopt
.import spar1, sopt1, calposp, incr
.import loupch1
.importzp cbp
.import inbuf
spar := spar1
sopt := sopt1

; From cmnd
.import cmnd2

; From ermes
.import ermes

; From ermtb
.import ermtb

; From stop-or-cont
.import StopOrCont

; From PrintAY
.import PrintAY

; From print1
.import print1

; .export Track, Head, Sector, Size, CRC

.import _strlen

; From main
.import __BSS_LOAD__, __BSS_SIZE__, __RAMEND__

;----------------------------------------------------------------------
;				Exports
;----------------------------------------------------------------------
.export _main
;.export _argc
;.export _argv

; Pour cmnd
.export cmnd_null
.export svzp
.export seter

.export comtb

; Pour ftdos, sedoric, dsk
;.export NS,NP
.export BUF_DSK, BUF_SECTOR


; Pour ermes
.export crlf1, out1
.export prfild, prnamd
.export seter1

xtrk = Track
psec = Sector
;xtrk = NP
;psec = NS
.exportzp xtrk, psec
.export drive


;----------------------------------------------------------------------
;			Librairies
;----------------------------------------------------------------------
; From dsk
.import _ReadSector, _ReadSector3, WaitResponse
.importzp Track, Sector

; From sedoric
.import sedoric_dir, dir_entry, sedoric_getdskInfo, sedoric_calcTrackSide

; From ftdos
.import ftdos_cat, CAT_Entry

;----------------------------------------------------------------------
; Defines / Constants
;----------------------------------------------------------------------
KERNEL_MAX_PATH_LENGTH = 49

	max_path := KERNEL_MAX_PATH_LENGTH
;DEBUG_HRS=1

;----------------------------------------------------------------------
;				Page Zéro
;----------------------------------------------------------------------
.zeropage
	unsigned short fp
;	dskname: .res 2
	unsigned short address

	; Utilisé par ftdos_fillfname et memcpy_screen
	unsigned short poin

	; Pour l'extract
	unsigned short extractptr

;----------------------------------------------------------------------
;				Variables
;----------------------------------------------------------------------
.segment "DATA"
	unsigned char dskname[max_path]
	unsigned char dskname2[max_path]

	; Utilisé par extract et fillname
	; Flag pour indiquer l'utilisation de méta caractères
	unsigned char fmeta

	unsigned char fname[13]

	yio: .res 1

	; Utilisés par search
	unsigned char search_track
	unsigned char search_sector
	unsigned char search_index

	; --------------------------------------------------------------------
	; Variables FTDOS
	; --------------------------------------------------------------------
	; *=$048C
	NLU: .res 1

	; --------------------------------------------------------------------
	; Tape Header
	; --------------------------------------------------------------------
	; $16 $16 $16 $16 $24 $ff $ff file_type autoexec >end <end >start <start $nn name $00
	tape_header:
		.byte $16, $16, $16, $16, $24, $ff, $ff
		unsigned char  tape_file_type
		unsigned char  tape_autoexec
		unsigned short tape_end
		unsigned short tape_start
		unsigned char  tape_dummy
		unsigned char orixfname[13]


	; --------------------------------------------------------------------
	; Pour l'extract
	; --------------------------------------------------------------------
	unsigned short file_start
	unsigned short file_end
	unsigned short file_size
	unsigned short file_exec

	unsigned char extractbuf
;	unsigned char extractcnt
	unsigned char nbpagemax

	; --------------------------------------------------------------------
	; Utilisé par hexdump
	; --------------------------------------------------------------------
	char TMP

;----------------------------------------------------------------------
;		Placer ces variables dans la librairie
;----------------------------------------------------------------------
;.segment "DATA"
;	_argc:
;		.res 1
;	_argv:
;		.res 2

;----------------------------------------------------------------------
; Variables et buffers
;----------------------------------------------------------------------
.segment "CODE"

	; /!\ ALIGNEMENT SUR UNE PAGE
	; Pour ReadSector
	unsigned char BUF_DSK[256]

	; Secteur lu
	unsigned char BUF_SECTOR[256]

	; Pour le FCB
	unsigned char BUF_FCB[256]


	unsigned char OSTYPE

	unsigned char cmnd_options

	char drive

;----------------------------------------------------------------------
;				ORIXHDR
;----------------------------------------------------------------------
; MODULE __MAIN_START__, __MAIN_LAST__, _main

;----------------------------------------------------------------------
;			Segments vides
;----------------------------------------------------------------------
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"

;----------------------------------------------------------------------
;				Programme
;----------------------------------------------------------------------
.segment "CODE"

.proc _main
		; Calcul de l'adresse du tampon pour l'extraction
		ldy	#>( (__BSS_LOAD__ + __BSS_SIZE__) & $ff00)
		lda	#<( (__BSS_LOAD__ + __BSS_SIZE__) )
		beq	skip
		iny
	skip:
		sty	extractbuf

		; Calcul de la taille du tampon pour l'extraction
		sec
		lda	#>__RAMEND__
		sbc	extractbuf
		sta	nbpagemax

		; Adresse de la ligne de commande
		ldy	#<BUFEDT
		lda	#>BUFEDT
		sty	cbp
		sta	cbp+1

		; Saute le nom du programme
		ldy	#$ff
	loop_pgm:
		iny
		lda	(cbp),y
		clc
		beq	eol

		cmp	#' '
		bne	loop_pgm

	eol:
		; Ici si on a trouvé un ' ' => C=1
		tya
		ldy	cbp+1
		adc	cbp
		sta	cbp
		bcc	loop_pgm_end

		iny
	loop_pgm_end:
		tya
		ldy	cbp

	getopt:
		jsr	sopt
		.asciiz "FSH"
		bcs	error

		; Si option obligatoire
		;cpx #$00
		;beq @end

		; -h ?
		cpx	#$20
		bne	cmnd_exec
		jmp	cmnd_help

	cmnd_exec:
		stx	OSTYPE

		; DEBUG
		;jsr cmnd_echo

		ldy	#$00
		lda	(cbp),y
		cmp	#'@'
		bne	go

		; Mode batch activé
		jsr	openbatch
		bcc	getopt
		bcs	error

	go:
		ldy	cbp
		lda	cbp+1

		; Exécute la commande
		jsr	cmnd2
		bcs	error

		;
		ldy	#$00
	skipcr:
		lda	(cbp),y
		beq	end
		cmp	#$0d
		bne	_calcposp
		iny
		bne	skipcr
		; Si débordement de Y
		beq	errEOF

	_calcposp:
		jsr	calposp
		bne	getopt


	error:
		jsr	ermes

	end:
		crlf
		rts

	errEOF:
		lda	#e4
		.byte	$2c

	errOpt:
	 	lda	#e15
	 	.byte	$2c
	errFopen:
		lda	#e13
		sec
		bcs	error
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_null
		; jsr PrintRegs
		; clc
		jmp	cmnd_help
		rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_unknown
		lda	#e15
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_help
        print	helpmsg
        clc
        rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_echo
		; Sauvegarde A,X,Y
		pha
		tya
		pha
		txa
		pha

		crlf

		ldy	#$ff
	loop:
		iny
		lda	(cbp),y
		beq	echo
		cmp	#$0d
		bne	loop

	echo:
		tya
		tax
		ldy	cbp
		lda	cbp+1
		jsr	PrintAY

		crlf

		pla
		tax
		pla
		tay
		pla
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_ls
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''

		jsr	opendsk
		bcs	error

		; OSTYPE: f s h x xxxx
		;         | | +--------> Help
		;         | +----------> Sedoric
		;         +------------> FTDOS

		bit	OSTYPE
		; jsr PrintRegs
		bpl	sedoric
		bvs	error_opt
		jsr	ftdos_ls
		bcc	close

	error_close:
		pha
		fclose	(fp)
		pla
		sec
		rts


	sedoric:
		bvc	error_opt

		; Lecture Piste 20, Secteur 1 pour avoir le nombre de pistes par face
		jsr	sedoric_getdskInfo
		bcs	error_close

		jsr	sedoric_ls
		bcs	error_close

	close:
		fclose	(fp)
		rts

	error_opt:
		lda	#e15
		sec
	error:
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_cat
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''

		jsr	opendsk
		bcs	error

		; Si on précise un modèle => ftdos_ls
		ldy	#$00
		lda	(cbp),y
		beq	cat
		; En mode batch on peut avoir un <CR>
		cmp	#$0d
		beq	cat
		jsr	ftdos_ls
		bcc	close

	error_close:
		pha
		fclose	(fp)
		pla
		sec
		rts

	cat:
		jsr	ftdos_cat
		bcs	error_close

	close:
		fclose	(fp)

		crlf

	error:
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_dir
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''

		jsr	opendsk
		bcs	error

		; Lecture Piste 20, Secteur 1 pour avoir le nombre de pistes par face
		jsr	sedoric_getdskInfo
		bcs	error_close

		; Si on précise un modèle => sedoric_ls
		ldy	#$00
		lda	(cbp),y
		beq	dir
		; En mode batch on peut avoir un <CR>
		cmp	#$0d
		beq	dir
		jsr	sedoric_ls
		bcc	close

	error_close:
		pha
		fclose	(fp)
		pla
		sec
		rts

	dir:
		jsr	sedoric_dir
		bcs	error_close

	close:
		fclose	(fp)

		crlf

	error:
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_dump
		; Initialise l'adresse pour l'affichage du dump

		ldx	#$80			; On veut des valeurs décimales
		jsr	spar
		.byte	Track, Sector, 0

		cpx	#%11000000
		bne	error_trk

		; 1 <= Secteur <= 17
		lda	Sector+1
		bne	error_trk
		lda	Sector
		beq	error_trk
		cmp	#17+1
		bcs	error_trk
		; sta	NS

		; 0 <= Piste <= 82
		lda	Track+1
		bne	error_trk
		lda	Track
		cmp	#(82+1)
		bcs	error_trk
		; sta	NP

		ldy	cbp
		lda	cbp+1
		; jsr	getfname
		; bcs	error

		jsr	opendsk
		bcs	error

		ldx	Sector
		; ldx	NS
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;bne	error_close
		bcs	error_close

		; Offset pour l'affichage: $0000
		lda	#$00
		tay
		jsr	hexdump

		fclose	(fp)
		rts

	error_close:
		pha
		fclose	(fp)
		pla
		sec
		rts

	error_trk:
		lda	#$b2

	error:
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_longhelp
		jsr	cmnd_help
		print	longhelp_msg
		clc
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_man
		fopen	manfile, O_RDONLY
		sta	fp
		stx	fp+1

		eor	fp+1
		beq	errFopen

		; Affiche la page man
		fread	SCREEN, #1120, 1, fp

		fclose	(fp)

		; Attend l'appui sur une touche
	loop:
		.byte	$00, XRD0
		beq	loop

		; Efface l'écran
		; Efface la ligne de status
		lda	#<SCREEN
		ldy	#>SCREEN
		sta	RES
		sty	RES+1
		ldy	#<(SCREEN+1*40)
		ldx	#>(SCREEN+1*40)
		lda	#' '
		.byte	$00, XFILLM

		; Efface le reste de l'écran
		print	#$0c

		; Fin
		clc
		rts

	errFopen:
	  	lda	#e13
	  	sec
	  	rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc cmnd_extract
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''

		; -Verbose: affiche l'évolution de l'extraction avec des '-' et '='
		; -Continue: continue si un fichier dépasse la taille maximale
		;            (défaut: stoppe l'extraction)
		; -Tape: génère un en-tête .tap (conflit avec slideshow -T)
		jsr	sopt
		.asciiz "VCT"
		bcs	error
		stx	cmnd_options

		; TODO: supprimer les lignes suivantes (pour la démo uniquement)
		;        force -v
		lda	cmnd_options
		ora	#$80
		sta	cmnd_options

		; Calcul de la taille du tampon pour l'extraction
		sec
		lda	#>__RAMEND__
		sbc	extractbuf
		sta	nbpagemax

		; OSTYPE: f s h x xxxx
		;         | | +--------> Help
		;         | +----------> Sedoric
		;         +------------> FTDOS

		bit	OSTYPE
		; jsr	PrintRegs
		bpl	sedoric
		bvs	error
		jmp	ftdos_extract

	sedoric:
		bvc	error
		jmp	sedoric_extract

	error:
		lda	#e15
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.ifdef SLIDESHOW
	.proc cmnd_slideshow
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''

		; -Verbose: affiche l'évolution de l'extraction avec des '-' et '='
		; -Continue: continue si un fichier dépasse la taille maximale
		;            (défaut: stoppe l'extraction)
		; -Hires
		; -Text
		jsr	sopt
		.asciiz "VCHT"
		bcs	error
		stx	cmnd_options

		; Hires
		lda	#$20
		sta	nbpagemax

		txa
		and	#%00110000
		beq	error
		cmp	#$30
		beq	error
		cmp	#$10
		bne	_slideshow
		; TEXT
		lda	#$05
		sta	nbpagemax

	_slideshow:

		; OSTYPE: f s h x xxxx
		;         | | +--------> Help
		;         | +----------> Sedoric
		;         +------------> FTDOS

		bit	OSTYPE
		; jsr	PrintRegs
		bpl	sedoric
		bvs	error
		jmp	ftdos_extract

	sedoric:
		bvc	error
		jmp	sedoric_extract

	error:
		lda	#e15
		sec
		rts

	.endproc
.endif

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc memcpy
		bit	cmnd_options
		bpl	suite
		print	#'-', SAVE

	suite:
		ldy	#$00

	loop:
		lda	BUF_SECTOR,y
		sta	(extractptr),y
		iny
		bne	loop

		inc	extractptr+1
		; dec extractcnt
		; bmi oom

		; Pas d'erreur

		jsr	StopOrCont
		; clc
		rts

	; oom:
	;	lda	#e1
	;	sec
	;	rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;	AY: Taille du fichier (A=MSB)
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc memsave
		sty	extractptr
		sta	extractptr+1

	.ifdef SILESHOW
		; Slideshow?
		lda	cmnd_options
		and	#%00110000
		beq	_memsave
		; AJouter une attente éventuelle
		jmp	memsave_screen
	.endif

	_memsave:
		; Fermeture du fichier .dsk
		fclose	(fp)

		bit	cmnd_options
		bpl	open_file
		crlf

	open_file:
		; Ouverture du fichier pour la sauvegarde
		fopen	orixfname, O_CREAT | O_WRONLY
		sta	fp
		stx	fp+1

		eor	fp+1
		beq	errFopen

		; Entête fichier .tap
		lda	cmnd_options
		and	#%00100000
		beq	no_header
		jsr	memsave_tape_header
		bcs	errorClose

	no_header:
		lda	extractptr
		ldy	extractptr+1
		jsr	SetByteWrite
		bcs	errorClose

		lda	#$00
		; sta	tmp
		; sta	tmp+1
		sta	extractptr
		lda	extractbuf
		sta	extractptr+1

	loop:
		; WriteReqData utilise extractptr
		; lda	extractptr
		; ldy	extractptr+1
		jsr	WriteReqData

		bit	cmnd_options
		bpl	suite
		print	#'=', SAVE

	suite:
		; Nombre d'octets écrits == 0?
		; Ajustement inutile dans ce cas
		; (on peut supprimer les 2 instructions suivantes si on veut
		;  gagner 2 octets)
		cpy	#$00
		;beq	fin
		beq	WriteNextChunk

		; Ajuste le pointeur
		clc
		tya
		adc	extractptr
		sta	extractptr
		bcc	skip
		inc	extractptr+1

	skip:
		; Ajuste le nombre d'octets lus
		; Peut être déplacé après la boucle et remplacé par uns soustraction
		; entre rwpoin et l'adresse de début
		; clc
		; tya
		; adc temp
		; sta temp
		; bcc WriteNextChunk
		; inc temp+1

	WriteNextChunk:
		jsr	ByteWrGo
		beq	loop

	fin:
		; Il faudrait vérifier que la taille écrite est bien la taille demandée.

		; Fermeture du fichier extrait
		fclose	(fp)

		; réouverture du .dsk
		jmp	reopendsk
		;rts

	errorClose:
		pha
		fclose	(fp)
		pla
		sec
		rts

	errFopen:
		lda	#e13
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;	AY: Taille du fichier (A=MSB)
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc memsave_screen
		lda	cmnd_options
		and	#%00110000
		cmp	#$20
		bne	_text

		; Cpoie vers l'écran HIRES
		.byte	$00, XHIRES

		lda	#<$A000
		sta	poin
		lda	#>$A000
		sta	poin+1
		bne	_copy_screen

	_text:
		cmp	#$10
		bne	error

		; Cpoie vers l'écran TEXT
		.byte	$00, XTEXT

		lda	#<$BB80
		sta	poin
		lda	#>$BB80
		sta	poin+1

	_copy_screen:
		; Sauvegarde le nombre de page de 256 octets pour la seconde boucle
		lda	extractptr+1
		pha

		; On commence par copier le reste (poids faible de la taille)
		; TODO: - BUG - Tester X par rapport à $00 pour éviter d'exécuter la booucle loop1
		; TODO: Inverser les 2 boucles?
		ldx	extractptr

		lda	#$00
		tay
		sta	extractptr
		lda	extractbuf
		sta	extractptr+1

	loop1:
		lda	(extractptr),y
		sta	(poin),y
		iny
		dex
		bpl	loop1

		; Ajuste le pointeur écran
		clc
		tya
		adc	poin
		sta	poin
		bcc	_inc
		inc	poin+1

	_inc:
		; Ajuste le pointeur source
		; TODO: en pratique, revient à remettre le poids faible le poids faible de la taille
		;       donc C ne peut pas être égale à 1 si extractptr est aligné sur une page
		;       remplacer tout de qui suit jusquau label 'suite' par: sty extractptr
		clc
		tya
		adc	extractptr
		sta	extractptr
		bcc	suite
		inc	extractptr+1

	suite:
		; Récupère le nombre de pages de 256 octets
		pla

		; Copie X pages
		tax
	loop2:

		ldy	#$00
	loop3:
		lda	(extractptr),y
		sta	(poin),y
		iny
		bne	loop3

		inc	extractptr+1
		inc	poin+1
		dex
		bne	loop2

		clc
		rts

	error:
		lda	#e15
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;	AY: Taille du fichier (A=MSB)
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc memsave_tape_header
		; $16 $16 $16 $16 $24 $ff $ff file_type autoexec >end <end >start <start $nn name $00
		; file_type: 0->Basic
		; Autoexec: 4 -> Autoexec
		; Si programme BASIC, taille du fichier +1 et ajouter un caractère à la fin

		; Calcul de la longueur de l'en-tête du fichier .tap

		; Calcule la longueur du nom du fichier
		; TODO: prendre plutôt le nom réel du fichier (à cause de Sedoric qui
		;       autorise un nom 9+3
		strlen	orixfname
		sty	tape_dummy
		iny
		tya
		clc
		adc	#14
		ldy	#$00
		jsr	SetByteWrite
		bcs	errorClose

		; Met à jour l'en-tête
		lda	file_start
		sta	tape_start+1
		lda	file_start+1
		sta	tape_start

		lda	file_end
		sta	tape_end+1
		lda	file_end+1
		sta	tape_end

		; Type: BASIC
		lda	#$00
		sta	tape_file_type
		; AUTOEXEC: True
		lda	#$01
		sta	tape_autoexec

		; Sauevgarde extractptr
		; TODO: Modifier WriteReqData pour utiliser AY
		lda	extractptr
		pha
		lda	extractptr+1
		pha

		lda	#<tape_header
		ldy	#>tape_header
		sta	extractptr
		sty	extractptr+1
		jsr	WriteReqData

		; Restaure extractptr
		pla
		sta	extractptr+1
		pla
		sta	extractptr

		jsr	ByteWrGo
		; On doit avoir un code erreur e11, sinon c'est qu'il manque des octets
		; dans l'en-tête
		bcc	error
		clc
		rts

	error:
	errorClose:
		; /!\ CODE ERREUR TEMPORAIRE, EN CHOISIR UN AUTRE
		lda	#$41
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;	AY: Pointeur vers le nom du fichier
;
; Sortie:
;	A,X,Y: Modifiés
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc toOrixFname
		sty	extractptr
		sta	extractptr+1

		ldx	#$00
		ldy	#$00

		bit	OSTYPE
		; jsr	PrintRegs
		bpl	sedoric

	loop:
		lda	(extractptr),y
		sta	orixfname,x
		cmp	#' '
		beq	skip
		inx
	skip:
		iny
		cpy	#12
		bne	loop

	end:
		lda	#$00
		sta	orixfname, x
		rts

		; On ne prend que les 8 premiers caractères
	sedoric:
		cpy	#12
		beq	end
		lda	(extractptr),y
		sta	orixfname,x
		cmp	#' '
		beq	skip2
		inx
	skip2:
		iny
		cpy	#8
		bne	sedoric
		iny
		lda	#'.'
		sta	orixfname,x
		inx
		bne	sedoric
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc ftdos_extract
		; Nom du fichier .dsk
	;	jsr getfname
	;	jcs error

		; Ouverture du fichier .dsk
		jsr	opendsk
		jcs	error

		; Modèle par défaut: *.*
		ldy	#$00
		lda	(cbp),y
		bne	extract
		ldy	#<default_pattern
		lda	#>default_pattern
		sty	cbp
		sta	cbp+1

	extract:
		; Nom du fichier à extraire
		ldy	cbp
		lda	cbp+1
		jsr	getfname
		jcs	error

		ldy	#<dskname
		lda	#>dskname

		jsr	ftdos_fillfname
		jcs	error_close

		;Recherche le fichier dans le fichier .dsk
		jsr	ftdos_search
		jcs	error

	extract_file:
		; Lecture emplacement FCB du fichier COPY.SCR
		; Nombre de secteur en BUF_SECTOR+$dc+16 et +$dc+17
		lda	BUF_SECTOR,y
		sta	Track
		ldx	BUF_SECTOR+1,y

		stx	Sector

	;---
		; Affiche le fichier trouvé
		crlf
		iny
		iny
		iny
		tya
		clc
		adc	#<BUF_SECTOR
		tay
		lda	#$00
		adc	#>BUF_SECTOR
		ldx	#12
		jsr	PrintAY
		jsr	toOrixFname

		ldx	Sector
	;---
		; Lecture du premier secteur du FCB
		lda	#<BUF_FCB
		ldy	#>BUF_FCB
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;jne	error_close
		jcs	error_close

		; Affiche l'adresse de chargement du fichier
		ldy	BUF_FCB+2
		lda	BUF_FCB+3
		sty	file_start
		sta	file_start+1
		;sty	address
		;sta	address+1
		jsr	printAddress
		print	#' '

		; Affiche la taille du fichier
		ldy	BUF_FCB+4
		lda	BUF_FCB+5
		sty	file_size
		sta	file_size+1
		;sty	address
		;sta	address+1
		jsr	printAddress
		print	#' '

		; Calcule l'adresse de fin du fichier
		clc
		lda	file_size
		adc	file_start
		sta	file_end
		lda	file_size+1
		adc	file_start+1
		sta	file_end+1

		; Ajuste l'adresse de fin
	;	lda	file_end
	;	bne	skip
	;	dec	file_end+1
	;  skip:
	;	dec	file_end


		crlf

		; Initialise l'adresse pour l'affichage du dump
		; Uniquement pour debug
	;	ldx #$00
	;	stx address
	;	stx address+1

		lda	#$00
		sta	extractptr
		lda	extractbuf
		sta	extractptr+1

		; Lecture du fichier
		; Nombre de secteurs à lire: MSB(Taille fichier)
		; Y = Index dans le FCP
		ldy	#$00

		lda	BUF_FCB+5
		beq	reste
		sta	NLU
		cmp	nbpagemax
		bcs	errOOM

		; Lecture des secteurs des fichiers
		ldy	#$00
	loop:
		lda	BUF_FCB+6,y
		sta	Track
		ldx	BUF_FCB+7,y
		;sta Sector
		iny
		iny

		; Sauvegarde de Y
		sty	yio

		; Lecture du secteur
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;bne	error_close
		bcs	error_close

	;	jsr	hexdump
		jsr	memcpy
		bcs	abort_close

		; /!\ ATTENTION: pb si le fichier utilise plus de 125 couples P/S
		; TODO: prende en compte yio == 0 (débordement vers un autre secteur
		; FCB possible)
		ldy	yio
		dec	NLU
		bne	loop

		; Lecture derniers octets
	reste:
		lda	BUF_FCB+4
		beq	suivant

		lda	BUF_FCB+6,y
		sta	Track
		ldx	BUF_FCB+7,y
		;sta	Sector
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;bne	error_close
		bcs	error_close

	;	jsr	hexdump
		jsr	memcpy
		bcs	abort_close

		; Sauvegarde du fichier
		ldy	file_size
		lda	file_size+1
		jsr	memsave
		bcs	error_close

		; Utilisation de meta caractères?
	next_file:
		bit	fmeta
		bpl	suivant
		; Oui
		jsr	ftdos_search_next
		jcc	extract_file
		cmp	#e13
		bne	error_close

	suivant:
		ldy	#$00
		lda	(cbp),y
		beq	fin
		cmp	#$0d
		jne	extract

	fin:
		fclose	(fp)
		clc
		rts

	errOOM:
		lda	#e1

	;.ifdef DEBUG
		bit	cmnd_options
		bvc	error_close
		; Pas d'abort si OOM, on passe au fichier suivant
		sec
		jsr	ermes
		jmp	next_file
	;.endif

	error_close:
		pha
		fclose	(fp)
		pla
		;lda	#$b0
	error:
		; jsr	PrintRegs
		sec
		rts

	abort_close:
		fclose	(fp)
		; TODO: Remonter une erreur ABORT à la place des print
		print	#'^'
		print	#'C'
		clc

		rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc ftdos_ls
		; [-- a placer dans la routine appelante
	;	jsr getfname
	;	bcs error

	;	jsr opendsk
	;	bcs error

		crlf

		; Modèle par défaut: *.*
		ldy	#$00
		lda	(cbp),y
		bne	ls
		ldy	#<default_pattern
		lda	#>default_pattern
		sty	cbp
		sta	cbp+1
		; --]

	ls:
		; Nom du fichier à extraire
		ldy	cbp
		lda	cbp+1
		jsr	getfname
		bcs	error

		ldy	#<dskname
		lda	#>dskname

		jsr	ftdos_fillfname
		bcs	error_close

		;Recherche le fichier dans le fichier .dsk
		jsr	ftdos_search
		bcs	error

	ls_file:
		jsr	CAT_Entry
		crlf

		jsr	StopOrCont
		bcs	fin

		; Utilisation de meta caractères?
		bit	fmeta
		bpl	suivant
		; Oui
		jsr	ftdos_search_next
		bcc	ls_file
		cmp	#e13
		bne	error_close

	suivant:
		ldy	#$00
		lda	(cbp),y
		beq	fin
		cmp	#$0d
		bne	ls

	fin:
	;	fclose	(fp)
		clc
		rts

	error_close:
	;	pha				; Sauvegarde le code erreur
	;	fclose	(fp)
	;	pla

	error:
		; jsr	PrintRegs
		sec
		rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc ftdos_search
		;Lecture 1er secteur du catalogue
		lda	#$14
		sta	Track
		ldx	#$02
	;	ldx	NS

	loadsector:
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;jne	error
		bcs	error

		ldy	#$04
		sty	yio

	compare:
		ldx	#$ff
		ldy	yio
		;Si la piste du FCB == $FF, le fichier est marqué comme supprimé
		lda	BUF_SECTOR,y
		cmp	#$ff
		beq	skip_entry

	loop:
		inx
		iny
		lda	fname,x
	  	beq	found
		cmp	#'?'
		beq	loop
		cmp	BUF_SECTOR+2,y
		beq	loop

	skip_entry:
		lda	yio
	::_search2 := *
		clc
		adc	#$12
		sta	yio
		bne	compare

		; On passe au secteur suivant
		lda	BUF_SECTOR+2
		sta	Track
		ldx	BUF_SECTOR+3
		bne	loadsector

		lda	#e13
		sec
		rts

	found:
		; Sauvegarde la position dans le catalogue pour search_next
		lda	Track
		sta	search_track
		lda	Sector
		sta	search_sector

		; Sortie avec Y := offset sur le début de l'entrée dans le catalogue
		ldy	yio
		sty	search_index
		clc
	;	lda	#e21
	;	sec
		rts

	error:
		;lda	#$b0
		;sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;	A: Code erreur si C=1
;	C: 0->Ok, 1->Erreur
;
; Variables:
;	Modifiées:
;		Track
;		Sector
;		yio
;	Utilisées:
;		search_track
;		search_sector
; Sous-routines:
;	_ReadSector
;	_search2
;----------------------------------------------------------------------
.proc ftdos_search_next
		; Vérifie si le buffer contient le secteur attendu
		lda	search_track
		cmp	Track
		bne	reload_track
		ldx	search_sector
		cpx	Sector
		beq	get_entry

	reload_track:
		lda	search_track
		sta	Track

	reload_sector:
		ldx	search_sector
		stx	Sector
		beq	error

		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		bcs	end

	get_entry:
		lda	search_index
		; sta	yio
		jmp	_search2

	error:
		lda	#$90
		sec
	end:
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc ftdos_fillfname
		sty	poin
		sta	poin+1

		; Initialise le tampon: '        .   '
		ldx	#11
		lda	#' '
	fill:
		sta	fname,x
		dex
		bpl	fill
		lda	#'.'
		sta	fname+8


		ldx	#$ff
		ldy	#$ff

	name:
		inx
		iny
		lda	(poin),y
		beq	fin

		cmp	#'.'
		beq	suite

		cmp	#'*'
		beq	fillname

		cpx	#$08
		bcs	error

		jsr	loupch1
		sta	fname,x
		bne	name

	fillname:
		lda	#'?'
	loop1:
		cpx	#$08
		beq	skip
		sta	fname,x
		inx
		bne	loop1

	suite:
		ldx	#$08

	skip:
		lda	(poin),y
		beq	fin
		cmp	#'.'
		beq	extension
		iny
		bne	skip
		beq	error

	extension:
		inx
		iny
		lda	(poin),y
		beq	fin

		cpx	#12
		beq	error

		cmp	#'.'
		beq	error

		cmp	#'*'
		beq	fillext

		jsr	loupch1
		sta	fname,x
		bne	extension

	fillext:
		lda	#'?'
	loop2:
		sta	fname,x
		inx
		cpx	#12
		bne	loop2

	fin:
		; Flag meta caractères
		lda	#$00
		sta	fmeta

		ldx	#11
	loop3:
		lda	fname,x
		cmp	#'?'
		beq	meta
		dex
		bpl	loop3
		bmi	fin2

	meta:
		dec	fmeta

	fin2:
		clc
		rts

	error:
		lda	#e10
		sec
		rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc sedoric_extract
		; Ouverture du fichier .dsk
		jsr	opendsk
		jcs	error

		; Lecture Piste 20, Secteur 1
		jsr	sedoric_getdskInfo
		jcs	error_close

	extract:
		; Modèle par défaut: *.*
		ldy	#$00
		lda	(cbp),y
		bne	extract_
		ldy	#<default_pattern
		lda	#>default_pattern
		sty	cbp
		sta	cbp+1

	extract_:
		; Nom du fichier à extraire
		ldy	cbp
		lda	cbp+1
		jsr	getfname
		jcs	error

		ldy	#<dskname
		lda	#>dskname

		jsr	sedoric_fillfname
		jcs	error_close

		;Recherche le fichier dans le fichier .dsk
		jsr	sedoric_search
		jcs	error

	extract_file:
		; Lecture emplacement FCB du fichier
		lda	BUF_SECTOR+12,y
		jsr	sedoric_calcTrackSide
		sta	Track
		ldx	BUF_SECTOR+13,y

		stx	Sector

		; Récupère la taille en secteurs du fichier
	;	lda BUF_SECTOR+14,y
	;	sta sedoric_fsize+1
	;	lda BUF_SECTOR+15
	;	and #$3f
	;	adc sedoric_fsize+1
	;	sta sedoric_fsize+1

	;---
		; Affiche le fichier trouvé
		crlf
		;iny
		;iny
		;iny

		; [-- peut être simplifié, BUF_SECTOR est aligné sur une page
		;     donc Y = #<BUF_SECTOR => lda #>BUF_SECTOR
		tya
		clc
		adc	#<BUF_SECTOR
		tay
		lda	#$00
		adc	#>BUF_SECTOR
		; --]

		ldx	#12
		jsr	PrintAY
		jsr	toOrixFname

		ldx	Sector
	;---
		; Lecture du premier secteur du FCB
		lda	#<BUF_FCB
		ldy	#>BUF_FCB
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;jne	error_close
		jcs	error_close

		; Affiche l'adresse de chargement du fichier
		ldy	BUF_FCB+4
		lda	BUF_FCB+5
		sty	file_start
		sta	file_start+1
		;sty	address
		;sta	address+1

		jsr	printAddress
		print	#' '

		; Affiche la taille du fichier
		; (adresse de fin - adresse de début+1)
		sec
		lda	BUF_FCB+6
		sta	file_end
		sbc	file_start
		sta	file_size
		tay
		lda	BUF_FCB+7
		sta	file_end+1
		sbc	file_start+1
		sta	file_size+1

		; Ajuste la taille
		;inc	file_size
		;bne	skip
		;inc	file_size+1

	skip:
		; Affiche la taille
		ldy	file_size
		lda	file_size+1
		;sty	address
		;sta	address+1
		jsr	printAddress
		print	#' '

		; Affiche l'adresse d'exécution
		;lda	address
		;pha
		;lda	address+1
		;pha
		ldy	BUF_FCB+8
		lda	BUF_FCB+9
		sta	file_exec
		sty	file_exec+1
		;sty	address
		;sta	address+1
		jsr	printAddress
		print	#' '

	;.ifdef DEBUG
		crlf
	;.endif
		; Restaure la taille du fichier
		;pla
		;sta	address+1
		;pla
		;sta	address

		; Initialise l'adresse pour l'affichage du dump
		; Uniquement pour debug
	;	ldx	#$00
	;	stx	address
	;	stx	address+1

		lda	#$00
		sta	extractptr
		lda	extractbuf
		sta	extractptr+1

		; Lecture des secteurs des fichiers
		; Y = Index dans le FCP
		; Offset à $0c pour le premier FCB
		ldy	#($0c-2)

		; Lecture du fichier
		; Nombre de secteurs à lire: MSB(Taille fichier)
		lda	file_size+1
		beq	reste
		sta	NLU

		; > mémoire disponible?
		cmp	nbpagemax
		bcs	errOOM

		; Lecture des secteurs des fichiers
		; Offset à $0c pour le premier FCB
		; ldy #($0c-2)
	loop:
		lda	BUF_FCB+2,y
		jsr	sedoric_calcTrackSide
		sta	Track
		ldx	BUF_FCB+3,y
		;stx	Sector
		iny
		iny

		; Sauvegarde de Y
		sty	yio

		; Lecture du secteur
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;bne	error_close
		bcs	error_close

	;	jsr	hexdump
		jsr	memcpy
		bcs	abort_close

		; /!\ ATTENTION: pb si le fichier utilise plus d'un secteur FCB
		; TODO: prende en compte yio == 0 (débordement vers un autre secteur
		; FCB possible)
		ldy	yio
		dec	NLU
		bne	loop

		; Lecture derniers octets
	reste:
		; Rest-t-il des octets?
		lda	file_size
		bne	extract_reste

		; La taille du fichier était nulle?
		lda	file_size+1
		beq	suivant
		bne	save

	extract_reste:
		lda	BUF_FCB+2,y
		jsr	sedoric_calcTrackSide
		sta	Track

		ldx	BUF_FCB+3,y
		;sta	Sector
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;bne	error_close
		bcs	error_close

	;	jsr	hexdump
		jsr	memcpy
		bcs	abort_close

		; Sauvegarde du fichier
	save:
		ldy	file_size
		lda	file_size+1
		jsr	memsave
		bcs	error_close

		; Utilisation de meta caractères?
	next_file:
		bit	fmeta
		bpl	suivant
		; Oui
		jsr	sedoric_search_next
		jcc	extract_file
		cmp	#e13
		bne	error_close

	suivant:
		ldy	#$00
		lda	(cbp),y
		beq	fin
		cmp	#$0d
		jne	extract

	fin:
		fclose	(fp)
		clc
		rts

	errOOM:
		lda	#e1

	;.ifdef DEBUG
		bit	cmnd_options
		bvc	error_close
		; Pas d'abort si OOM, on passe au fichier suivant
		sec
		jsr	ermes
		jmp	next_file
	;.endif

	error_close:
		pha
		fclose	(fp)
		pla
		;lda	#$b0

	error:
		; jsr	PrintRegs
		sec
		rts

	abort_close:
		fclose	(fp)

		; TODO: Remonter une erreur ABORT à la place des print
		print	#'^'
		print	#'C'
		clc

		rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc sedoric_ls
		; [-- a placer dans la routine appelante
	;	jsr getfname
	;	bcs error

	;	jsr opendsk
	;	bcs error

		crlf

		ldy	#$00
		lda	(cbp),y
		bne	ls
		ldy	#<default_pattern
		lda	#>default_pattern
		sty	cbp
		sta	cbp+1
		; --]

			; Lecture Piste 20, Secteur 1
		jsr	sedoric_getdskInfo
		bcs	error_close

	ls:
		; Nom du fichier à extraire
		ldy	cbp
		lda	cbp+1
		jsr	getfname
		bcs	error

		ldy	#<dskname
		lda	#>dskname

		jsr	sedoric_fillfname
		bcs	error_close

		;Recherche le fichier dans le fichier .dsk
		jsr	sedoric_search
		bcs	error

	ls_file:
		jsr	dir_entry
		crlf

		jsr	StopOrCont
		bcs	fin

		; Utilisation de meta caractères?
		bit	fmeta
		bpl	suivant
		; Oui
		jsr	sedoric_search_next
		bcc	ls_file
		cmp	#e13
		bne	error_close

	suivant:
		ldy	#$00
		lda	(cbp),y
		beq	fin
		cmp	#$0d
		bne	ls

	fin:
	;	fclose	(fp)
		clc
		rts

	error_close:
	;	pha				; Sauvegarde le code d'erreur
	;	fclose	(fp)
	;	pla

	error:
		; jsr	PrintRegs
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc sedoric_search
		;Lecture 1er secteur du catalogue
		lda	#$14
		sta	Track
		sta	search_track
		ldx	#$04
		stx	search_sector
	;	ldx	NS

	loadsector:
		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		;cmp	#CH376_USB_INT_SUCCESS
		;jne	error
		bcs	error

		ldy	#$10
		sty	yio

	compare:
		ldx	#$ff
		ldy	yio
		;Si la piste du FCB == $FF, le fichier est marqué comme supprimé
		lda	BUF_SECTOR+13,y
		;cmp	#$ff
		beq	skip_entry

		dey			; Compense le INY
	loop:
		inx
		iny
		lda	fname,x
	  	beq	found
		cmp	#'?'
		beq	loop
		cmp	BUF_SECTOR,y
		beq	loop

	skip_entry:
		lda	yio
	::_search2_sed := *
		clc
		adc	#$10
		sta	yio
		bne	compare

		; On passe au secteur suivant
		tay			; A=0 => Y=0
		lda	BUF_SECTOR,y
		jsr	sedoric_calcTrackSide
		sta	Track
		sta	search_track
		iny
		ldx	BUF_SECTOR,y
		stx	search_sector
		bne	loadsector

		lda	#e13
		sec
		rts

	found:
		; Sauvegarde la position dans le catalogue pour search_next
	;	lda	Track
	;	sta	search_track
	;	lda	Sector
	;	sta	search_sector

		; Sortie avec Y := offset sur le début de l'entrée dans le catalogue
		ldy	yio
		sty	search_index
		clc
	;	lda	#e21
	;	sec
		rts

	error:
		;lda	#$b0
		;sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;	A: Code erreur si C=1
;	C: 0->Ok, 1->Erreur
;
; Variables:
;	Modifiées:
;		Track
;		Sector
;		yio
;	Utilisées:
;		search_track
;		search_sector
; Sous-routines:
;	_ReadSector
;	_search2
;----------------------------------------------------------------------
.proc sedoric_search_next
		; Vérifie si le buffer contient le secteur attendu
		lda	search_track
		cmp	Track
		bne	reload_track
		ldx	search_sector
		cpx	Sector
		beq	get_entry

	reload_track:
		lda	search_track
		sta	Track

	reload_sector:
		ldx	search_sector
		stx	Sector
		beq	error

		lda	#<BUF_SECTOR
		ldy	#>BUF_SECTOR
		jsr	_ReadSector
		bcs	end

	get_entry:
		lda	search_index
		; sta	yio
		jmp	_search2_sed

	error:
		lda	#$90
		sec
	end:
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc sedoric_fillfname
		sty	poin
		sta	poin+1

		; Initialise le tampon: '            '
		ldx	#11
		lda	#' '
	fill:
		sta	fname,x
		dex
		bpl	fill

		; FTDOS UNIQUEMENT
		;lda	#'.'
		;sta	fname+8


		ldx	#$ff
		ldy	#$ff

	name:
		inx
		iny
		lda	(poin),y
		beq	fin

		cmp	#'.'
		beq	suite

		cmp	#'*'
		beq	fillname

		;cpx	#$08			; FTDOS
		cpx	#$09			; SEDORIC
		bcs	error

		jsr	loupch1
		sta	fname,x
		bne	name

	fillname:
		lda	#'?'
	loop1:
		;cpx	#$08			; FTDOS
		cpx	#$09			; SEDORIC
		beq	skip
		sta	fname,x
		inx
		bne	loop1

	suite:
		;ldx	#$08			; FTDOS
		ldx	#$09			; SEDORIC

	skip:
		lda	(poin),y
		beq	fin
		cmp	#'.'
		; beq	extension		; FTDOS
		beq	extension-1		; SEDORIC
		iny
		bne	skip
		beq	error

		dex				; SEDORIC (compensation du premier INX, pas de '.')
	extension:
		inx				; FTDOS
		iny
		lda	(poin),y
		beq	fin

		cpx	#12
		beq	error

		cmp	#'.'
		beq	error

		cmp	#'*'
		beq	fillext

		jsr	loupch1
		sta	fname,x
		bne	extension

	fillext:
		lda	#'?'
	loop2:
		sta	fname,x
		inx
		cpx	#12
		bne	loop2

	fin:
		; Flag meta caractères
		lda	#$00
		sta	fmeta

		ldx	#11
	loop3:
		lda	fname,x
		cmp	#'?'
		beq	meta
		dex
		bpl	loop3
		bmi	fin2

	meta:
		dec	fmeta

	fin2:
		clc
		rts

	error:
		lda	#e10
		sec
	rts
.endproc




;**********************************************************************
; Fin du programme
;**********************************************************************


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc printAddress
	;	print #' '
	;	lda address+1
	;	jsr PrintHexByte
	;	lda address
	;	jsr PrintHexByte
	;	print #':'
	;	rts

	; Version pour Librairie (sans utilisation de 'address')
	; Entrée; AY = adresse (A=MSB, Y=LSB)
	; /!\ Verifier que PrintHexByte préserve au moins Y
	;     et que XWR0 conserve A et Y
		print	#' ', SAVE
		jsr	PrintHexByte
		tya
		jsr	PrintHexByte
		print	#':', SAVE
		rts
.endproc

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc getfname
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''
		;sty dskname
		;sta dskname+1

		ldy	#$ff
	loop:
		iny
		lda	(cbp),y
		sta	dskname,y
		beq	endloop
		cmp	#$0d
		beq	endloop
		cmp	#' '
		bne	loop

	endloop:
		cpy	#00
		beq	error_no_filename

		; Termine la chaîne par un nul
	;	cmp	#$00
	;	beq	ajuste

		lda	#$00
		;sta	(cbp),y
		sta	dskname,y
		;iny

		; Ajuste cbp
		jsr	calposp
		rts

	error_no_filename:
		lda	#e12
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;	A: Code erreur
;	C: 0-> Ok,1-> Erreur
;
; Variables:
;	Modifiées:
;		BUF_SECTOR
;		fp
;
;	Utilisées:
;		dsk_header
;
; Sous-routines:
;	getfname
;	XOPEN
;----------------------------------------------------------------------
.proc opendsk
		; AY : adresse du paramètre suivant
		; cbp:   ''          ''

		jsr	getfname
		bcs	error

		; Copie le nom du fichier .dsk pour que "extract" puisse le réouvrir
		; TODO? : modifier getfname pour prendre l'adresse de dskname en paramètre
		ldy	#$ff
	copy:
		iny
		lda	dskname,y
		sta	dskname2,y
		beq	open
		bne	copy

	open:
		fopen	dskname, O_RDONLY
		sta	fp
		stx	fp+1

		eor	fp+1
		beq	errFopen

		fread	BUF_SECTOR, #08, 1, fp
		ldy	#$07
	loop:
		lda	BUF_SECTOR,y
		cmp	dsk_header,y
		bne	errFormat
		dey
		bpl	loop

		clc
		rts

	errFormat:
		fclose	(fp)
	 	lda	#e29
	 	.byte	$2c

	errFopen:
		lda	#e13

	error:
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc reopendsk
		ldy	#$00
		lda	dskname2,y
		beq	errNodsk

		dey
	copy:
		iny
		lda	dskname2,y
		sta	dskname,y
		beq	open
		bne	copy

	open:
		fopen	dskname, O_RDONLY
		sta	fp
		stx	fp+1

		eor	fp+1
		beq	errFopen

		clc
		rts

	errNodsk:
		lda	#e12
		.byte	$2c

	errFopen:
		lda	#e13

	error:
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc openbatch
		; Mode batch activé
		ldx	#cbp
		jsr	incr
		ldy	cbp
		lda	cbp+1
		jsr	getfname
		bcs	errFopen

		; rempli de buffer de $00 au cas où...
		lda	#$00
		ldx	#80
	loop:
		sta	inbuf,x
		dex
		bpl	loop

		fopen	dskname, O_RDONLY
		sta	fp
		stx	fp+1

		eor	fp+1
		beq	errFopen

		; TODO: Tester le code de retour de fread
		fread	inbuf, #79, 1, fp
		fclose	(fp)

		; Remplace les $0a par des $0d
		ldx	#81
	loop1:
	 	dex
		beq	go_batch
		lda	inbuf,x
		cmp	#$0a
		bne	loop1
		lda	#$0d
		sta	inbuf,x
		bne	loop1

	go_batch:
		ldy	#<inbuf
		lda	#>inbuf
		;bne	getopt			; >inbuf ne peut pas être nul

		; Met à jour cbp
		sty	cbp
		sta	cbp+1
		clc
		rts

	errFopen:
		lda	#e13
		sec

	error:
		rts
.endproc


;----------------------------------------------------------------------
;				DATAS
;----------------------------------------------------------------------
.segment "RODATA"

	helpmsg:
	    .byte $0a, $0d
	    .byte $1b,"C         Disk images utility\r\n\n"
	    .byte " ",$1b,"TSyntax:",$1b,"P\r\n"
	    .byte "    dsk-util",$1b,"A-h",$1b,"G\r\n"
	    .byte "    dsk-util",$1b,"B[-f|-s]",$1b,"A<cmd>",$1b,"B[dsk]",$1b,"B[...]\r\n"
	    .byte "    dsk-util",$1b,"A@filename"
	    .byte "\r\n"
;	    .byte "    dsk-util",$1b,"B[-f|-s]",$1b,"Als",$1b,"G<file.dsk>",$1b,"B[...]"
;	    .byte "\r\n"
;	    .byte "    dsk-util",$1b,"Acommand",$1b,"Bopts",$1b,"G<file.dsk>\r\n"
	    .byte $00

	longhelp_msg:
	    .byte "\r\n"
	    .byte " ",$1b,"TOptions:",$1b,"P\r\n"
	    .byte "   ",$1b,"A-h",$1b,"Gdisplay command syntax\r\n"
	    .byte "   ",$1b,"A-f",$1b,"GFTDOS image file\r\n"
	    .byte "   ",$1b,"A-s",$1b,"GSedoric image file\r\n"
	    .byte "\r\n"
	    .byte " ",$1b,"TCommands:",$1b,"P\r\n"
	    .byte "   ",$1b,"Acat ",$1b,"Gdisplay ftdos catalog\r\n"
	    .byte "   ",$1b,"Adir ",$1b,"Gdisplay sedoric directory\r\n"
	    .byte "   ",$1b,"Adump",$1b,"Btrack,sector",$1b,"Gsector hexdump\r\n"
	    .byte "   ",$1b,"Aget ",$1b,"Bdsk filespec...",$1b,"Gget files\r\n"
	    .byte "   ",$1b,"Als  ",$1b,"Bdsk filespec...",$1b,"Glist files\r\n"
	    .byte "   ",$1b,"Ahelp",$1b,"Gthis help\r\n"
	    .byte "\r\n"
	    .byte " ",$1b,"TExamples:",$1b,"P\r\n"
	    .byte "    dsk-util cat ftdos.dsk\r\n"
	    .byte "    dsk-util dir sedoric3.dsk\r\n"
	    .byte "    dsk-util dump 20,2 ftdos.dsk\r\n"
	    .byte "    dsk-util -f ls ftdos.dsk *.bas c*.*\r\n"
	    .byte "    dsk-util -f get ftdos.dsk *.bas"
	    .byte $00

	manfile:
	    .asciiz "/USR/SHARE/MAN/DSK-UTIL.HLP"

	dsk_header:
		.byte "MFM_DISK"

	default_pattern:
		.asciiz "*.*"

;----------------------------------------------------------------------
;				TABLES
;----------------------------------------------------------------------
.segment "RODATA"

	.macro add_cmnd command, address, len
		; command: nom de la commande (chaîne)
		; address: adresse d'exécution de la commande
		; len    : longueur minimale poue la reconnaissance de la commande
		;          (défaut: longueur de "command")


		; opt: 1 zi0 llll
		; z: 1 -> save zero page
		; i: 1 -> i/o command (exec via comf2)
		; llll: command name length (minimum)
		.if .not .blank(len)
			.byte (len & $0f) | $80
		.else
			.byte (.strlen(command) & $0f) | $80
		.endif

		.word address

		.if .strlen(command) > 0
			.byte command
		.endif

	.endmacro

	comtb:
		add_cmnd "CAT",  cmnd_cat,      1
		add_cmnd "DIR",  cmnd_dir,      2
		add_cmnd "LS",   cmnd_ls,       1
		add_cmnd "DUMP", cmnd_dump,     2
		add_cmnd "HELP", cmnd_longhelp, 1
		add_cmnd "MAN",  cmnd_man,      1
		add_cmnd "EXTRACT", cmnd_extract, 1
		add_cmnd "GET",  cmnd_extract, 1
.ifdef SLIDESHOW
		add_cmnd "SLIDESHOW", cmnd_slideshow, 1
.endif
		add_cmnd "",     cmnd_unknown


;======================================================================
;			Fonctions utilitaires
;======================================================================


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		TMP
;		address
;
;	Utilisées:
;		BUF_SECTOR
;
; Sous-routines:
;	StopOrCont
;	printAddress
;	PrintHexByte
;----------------------------------------------------------------------
;.import StopOrCont, printAddress, PrintHexByte
;.import address, BUF_SECTOR

.segment "RODATA"
	charline:
		.byte "|........"
		.byte $0a, $0d
		.byte $00


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.segment "CODE"
.export hexdump

.proc hexdump
		sty	address
		sta	address+1

		ldx	#$20
		stx	TMP

		crlf

		; Y: poids faible de l'offset affiché
		; /!\ suppose que address est aligné sur une page
		ldy	#$00

	print_line:
		jsr	StopOrCont
		bcs	end

		; Y contient le poids faible
		; /!\ suppose que address est aligné sur une page
		lda	address+1
		jsr	printAddress
		ldx	#$00
	loop:
	 	inx
		lda	#'.'
		sta	charline,x
		lda	BUF_SECTOR,y

		cmp	#' '
		bcc	suite
		cmp	#'z'+1
		bcs	suite
		sta	charline,x

	suite:
		print	#' ', SAVE
		jsr	PrintHexByte

		iny
		tya
		and	#$07
		bne	loop

		; /!\ A modifier si le dump ne commence pas au début d'une page
		sty	address

		print	charline

		; recharge Y car détruit par le print charline, NOSAVE
		ldy	address

		dec	TMP
		bne	print_line

		; /!\ A modifier si le dump ne commence pas au début d'une page
		inc	address+1

		; BRK_KERNEL XCRLF

	end:
		rts
.endproc


;===========================================================================
;		Gestion des erreurs
;===========================================================================
.segment "CODE"

;----------------------------------------------------------------------
;
;----------------------------------------------------------------------
.proc crlf1
		crlf
		rts
.endproc

;----------------------------------------------------------------------
;
;----------------------------------------------------------------------
.proc out1
		cputc
		rts
.endproc

;----------------------------------------------------------------------
;
;----------------------------------------------------------------------
.proc prfild
		print	dskname
		rts
.endproc

;----------------------------------------------------------------------
;
;----------------------------------------------------------------------
.proc prnamd
		print	dskname
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
seter:
seter1:
		rts

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
svzp:
		rts



;===========================================================================
;		CH376
;===========================================================================

;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc SetByteWrite
		pha

		lda	#CH376_BYTE_WRITE
		sta	CH376_COMMAND

		pla
		sta	CH376_DATA
		sty	CH376_DATA

		jsr	WaitResponse
		cmp	#CH376_USB_INT_SUCCESS
		bne	write1
	end:
		clc
		rts

	write1:
	 	; Dans le cas de l'écriture d'un seul octet le CH376 répond INT_DISK_WRITE
	 	; et non INT_SUCCESS
	 	; TODO: Vérifier qu'on est bien dans ce cas avec YA==$01
		cmp	#CH376_USB_INT_DISK_WRITE
		beq	end

	error:
		lda	#e11
		sec
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc WriteReqData
	rwpoin = extractptr
	;	sta	rwpoin
	;	sty	rwpoin+1

		ldy	#$00
		lda	#CH376_WR_REQ_DATA
		sta	CH376_COMMAND

		ldx	CH376_DATA
		beq	end

	loop:
		lda	(rwpoin),y
		sta	CH376_DATA
		iny
		dex
		bne	loop
	end:
		rts
.endproc


;----------------------------------------------------------------------
;
; Entrée:
;
; Sortie:
;
; Variables:
;	Modifiées:
;		-
;	Utilisées:
;		-
; Sous-routines:
;	-
;----------------------------------------------------------------------
.proc ByteWrGo
		lda	#CH376_BYTE_WR_GO
		sta	CH376_COMMAND

		jsr	WaitResponse
		cmp	#CH376_USB_INT_DISK_WRITE
		bne	error
		clc
		rts

	error:
		lda	#e11
		sec
		rts
.endproc


; ******************************************************************************
;
; ******************************************************************************
