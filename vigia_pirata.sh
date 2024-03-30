#!/bin/sh

#Função para demonstrar menu do programa
mostrarAjuda(){
    echo "Uso: $0 [-f <ficheiro>] [{-v | -p <diretoria> [<diretoria>]}]"
	echo "    -f : Indicação do nome do ficheiro onde a base de dados será guardada (Por defeito será $HOME/.protecao)"
	echo "    -v : Verifica alterações em ficheiros desde que foram protegidos"
	echo "    -p : Protege e guarda informação acerca de uma ou mais diretorias"	
	exit 1 # Sai do programa
}

criarDB(){
    # Guarda a localização do ficheiro com a db e "remove-a" do $@
	db=$1; shift # É utilizado para ser possivel aceder aos argumentos restantes após guardar a localização do ficheiro da bd na variável db
	
    # Verifica se não existe argumentos (diretorias), caso não exista mostra uma mensagem de erro
	if [ $# -eq 0 ]; then
		echo "Erro: Argumentos em falta em -p\nIndique pelo menos uma diretoria\n" >&2
		mostrarAjuda >&2
	fi

    # Remove o ficheiro da DB
	rm -f $db 2>/dev/null

    # Guarda os caminhos e cria dois ficheiros temporários (com o numero do processo) para guardar a nova bd e os caminhos das diretorias
	tmpDB="/tmp/vigia_pirata_criarDB$$"
	tmpPaths="/tmp/vigia_pirata_criarDB$$_paths"
	echo -n > $tmpDB > $tmpPaths

    # Percorre as diretorias em argumentos até acabarem
	until [ $# -eq 0 ]
	do
		# Retira o path inteiro da diretoria com recurso ao comando "realpath" e guarda-o na variável pathRaiz
		pathRaiz=`realpath $1`
		echo -n "$pathRaiz " >> $tmpPaths
		
		# Verifica se o caminho corresponde ou não a uma diretoria, se não corresponder é mostrada uma mensagem de erro
		if [ ! -d "$pathRaiz" ]; then
			echo "Erro: \"$pathRaiz\" não é uma diretoria" >&2
			
			# Retira a "não diretoria" do $@ e continua o ciclo
			shift; continue
		fi
		echo -n "$pathRaiz\t"
		
		# O IFS passa a ser o \n (newline)
        # Esta configuração do IFS permite que a leitura de uma variável ou a saída de um comando seja dividida em linhas, mesmo se as linhas contenham espaços ou outros caracteres que normalmente seriam tratados como delimitadores pelo IFS padrão.
		OIFS=$IFS; IFS=""

        # Procura com o comando find todas as subdiretorias da diretoria atual (inclusive) e percorre-as [não inclui diretorias escondidas]
		for pathDir in `find $pathRaiz -type d -not -path "*/.*" 2>/dev/null`; do
			# Procura com o comando find todos os ficheiros dentro da diretoria e imprime-os num formato semelhante ao ls -l
			# formato: pathName perm user group size date(dd/mm/yyyy) time(hh:mm)
			find $pathDir -mindepth 1 -maxdepth 1 -type f -printf "%p\t%M\t%u\t%g\t%s\t%Td/%Tm/%TY\t%TH:%TM\n" 2>/dev/null >> "$tmpDB"
                #%p: Substituído pelo caminho do arquivo.
                #%M: Substituído pelas permissões do arquivo.
                #%u: Substituído pelo nome do usuário proprietário do arquivo.
                #%g: Substituído pelo nome do grupo proprietário do arquivo.
                #%s: Substituído pelo tamanho do arquivo em bytes.
                #%Td/%Tm/%TY: Substituído pela data de modificação do arquivo no formato dia/mês/ano.
                #%TH:%TM: Substituído pela hora de modificação do arquivo no formato hora:minuto.
		done
		
		# O IFS passa a ser o " " (espaço) novamente e Retira a diretoria do $@
        # Restauração do valor original
		IFS=$OIFS
		shift; echo "Done"
	done
	
    # Cria o ficheiro da db e guarda nele as paths das diretorias e os registos referentes a ficheiros do ficheiro de db temporário
	# (os registos são ordenados por nome pelo comando sort, que também remove linhas duplicadas)
	cp -f $tmpPaths $db 2>/dev/null
	echo >> $db
	grep -Ee "-(r|w|x|-){9}" $tmpDB 2>/dev/null | sort -u >> $db
	
	# Remove os ficheiros temporários e altera as permissões da db para que seja READ_ONLY
	rm -f $tmpDB $tmpPaths 2>/dev/null
	chmod 444 $db 2>/dev/null
}

# Função para proteger as diretorias no ficheiro de base de dados
proteger() #$db $diretorias...
{
	criarDB $@
	echo "\nBase de dados de proteção $1 criada"
}

# Função para mostrar as informações do ficheiro, de acordo com a string passada
mostrarInfo() # pathName perm user group size date(dd/mm/yyyy) time(hh:mm)
{	
	echo $* | awk -F "\t" '{ printf "%s\nUSER=%s, GROUP=%s, SIZE=%s, PERM=%s, CHANGE TIME=%s %s\n", $1, $3, $4, $5, substr($2, 2), $6, $7 }'
}

# Função para verificar o estado atual das diretorias com os registos da bd
verificar() #$db
{
	# Verifica se a DB existe, se não existir mostra uma mensagem de erro
	if [ ! -f "$1" ]; then
		echo "Erro: O ficheiro $1 não existe! \n" >&2
		mostrarAjuda >&2
	fi
	
	# Guarda a primeira linha da DB (que contém as diretorias)
	dirs=`head -1 $1`
	
	# Cria uma DB temporária para comparar as diferenças entre as duas DBs 
	verDB="/tmp/vigia_pirata_verificarDB$$"
	criarDB $verDB $dirs 1>/dev/null 2>/dev/null
	
	# Cria 3 ficheiros temporários para guardar os ficheiros adicionados, alterados e eliminados e outro para usar em casos de input=output no grep
	fgrep="/tmp/vigia_pirata_verificar$$_grep"; fa="/tmp/vigia_pirata_verificar$$_added"
	fc="/tmp/vigia_pirata_verificar$$_changed"; fd="/tmp/vigia_pirata_verificar$$_deleted"
	echo -n > $fc > $fd; 
	tail -n +2 $verDB 2>/dev/null > $fa # ignora a primeira linha da DB

	# O IFS passa a ser o \n (newline)
	OIFS=$IFS; IFS="
"
	# Percorre as linhas da DB antiga (ignora a primeira linha) e guarda os ficheiros adicionados, alterados e eliminados nos respectivos ficheiros
	for line in `tail -n +2 $1 2>/dev/null`; do
		# Retira o nome do caminho do ficheiro atual
		filePath=`echo $line | cut -f 1`
		
		# Remove ficheiros repetidos (ficando apenas os ficheiros adicionados)
		grep -v "$filePath	" $fa 2>/dev/null > $fgrep; mv $fgrep $fa
		
		# Verifica se o ficheiro não existe na nova DB
		if ! (grep "$filePath	" $verDB 2>/dev/null > $fgrep)
		then # Não existe, então foi eliminada (adiciona-o aos ficheiros removidos)
			echo "$line" >> $fd
		else # Existe, então a nova linha deverá ser diferente da linha antiga (para que seja uma alteração)
			newLine=`cat $fgrep`
			if [ "$newLine" != "$line" ]; then
				echo "$line\n$newLine" >> $fc
			fi
		fi
	done

	# Calcula o nr de diferenças (baseado no nr de linhas dos ficheiros temporários) e verifica se não existiram alterações
	nDiffs=`wc -l $fa $fc $fd 2>/dev/null | tail -1 | sed 's/^ *//' | cut -d " " -f 1`
	if [ $nDiffs -eq 0 ]; then # Se não existirem mostra uma mensagem
		echo "Não existem alterações!"
	else # Se existirem percorre os ficheiros e mostra as alteracões
		# Percorre as linhas do ficheiro de adicionados e mostra as informações com recurso à função mostrarInfo
		for line in `cat $fa`; do
			echo -n "Ficheiro adicionado: "; mostrarInfo "$line"; echo
		done
		
		# Percorre as linhas do ficheiro de removidos e mostra as informações com recurso à função mostrarInfo
		for line in `cat $fd`; do
			echo -n "Ficheiro removido: "; mostrarInfo "$line"; echo
		done
		
		# Percorre as linhas do ficheiro de alterados e mostra as informações antigas e novas com recurso à função mostrarInfo
		i=0
		for line in `cat $fc`; do
			line=`mostrarInfo "$line"`
			if [ `expr $i % 2` -eq 0 ]; then
				echo -n "Ficheiro alterado: "; echo "$line" | head -1
				echo -n "Informação inicial: "; echo "$line" | tail -1
			else
				echo -n "Informação atual:   "; echo "$line" | tail -1; echo
			fi
			i=`expr $i + 1`
		done
	fi

	# O IFS passa a ser o " " (espaço) novamente e Remove os ficheiros temporários
	IFS=$OIFS
	rm -f $fgrep $fa $fc $fd $verDB 2>/dev/null
}

# Inicialização de variáveis que guardam a ação e a localização da db
acao=""
pathDB="$HOME/.protecao"

# Percorre pelas opções e guarda a opção atual na variável opt
while getopts ":hf:vp" opt; do
	# A variável opt poderá ser uma das opções da optstring (h, f, v e p), : (se não for dado nenhum argumento para uma opção que necessita) ou ? (para outras opções não referidas na optstring) 
	case "$opt" in
		f) # Guarda o argumento ($OPTARG) como sendo a localização da db
			pathDB=`realpath "$OPTARG"` ;;
		p) # Verifica se a variável acao é nula
			if [ -z $acao ]; then 
				# Atribui a ação proteger (correspondente à opção p)
				acao=proteger
			else # Se já estiver preenchida quer dizer que as opções -p e -v estão a ser usadas simultaneamente (mostra uma mensagem de erro)
				echo "Erro: Uso de -p e -v simultaneamente\n" >&2
				mostrarAjuda >&2
			fi ;;
		v) # Verifica se a variável acao é nula
			if [ -z $acao ]; then
				# Atribui a ação verificar (correspondente à opção v)
				acao=verificar
			else # Se já estiver preenchida quer dizer que as opções -p e -v estão a ser usadas simultaneamente (mostra uma mensagem de erro)
				echo "Erro: Uso de -p e -v simultaneamente\n" >&2
				mostrarAjuda >&2
			fi ;;
		h) # Mostra a sintaxe do programa
			mostrarAjuda ;;	
		:) # Mostra uma mensagem de erro porque não foi dado nenhum argumento a uma opção que necessita de um argumento (-f)
			echo "Erro: Argumento em falta em -$OPTARG\n" >&2
			mostrarAjuda >&2 ;;
		*) # Mostra uma mensagem de erro porque foi encontrada uma opção inválida (não referida na optstring)
			echo "Erro: Opção inválida -$OPTARG\n" >&2
			mostrarAjuda >&2 ;;
	esac
done

# "Retira" os argumentos relativos às opções do $@ ($OPTIND - 1 dá o número de argumentos usados para as opções)
shift `expr $OPTIND - 1`

# Verifica se a variável acao é nula, e se for é atribuida a ação verificar (por padrão)
if [ -z $acao ]; then
	acao=verificar
fi

# Chama a função referente à ação e passa por argumentos a localização da db e os argumentos do programa (diretorias)
$acao $pathDB $@

