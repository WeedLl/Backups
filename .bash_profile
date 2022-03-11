#_______________________________________________ Дефолтные настройки ______________________________

PATH=/Library/Frameworks/Python.framework/Versions/3.10/bin:${PATH}
export PATH
alias python=python3
alias pip="/Library/Frameworks/Python.framework/Versions/3.10/bin/pip3"


#_______________________________________________ SmartMooving ______________________________________
alias Dpython='cd ~/Documents/Python'
alias Dpycharm='cd ~/PycharmProjects'
alias Dbackup='cd ~/Documents/For\ Sys/Backup'

#_______________________________________________ ShortCat __________________________________________
## Vim
alias default_vim='/usr/bin/vim'
alias vim='/Applications/Програмирование/MacVim.app/Contents/MacOS/Vim'
alias mac_vim='open -a /Applications/Програмирование/MacVim.app'
## FZF
alias fopen='open $(fzf)'

alias nopen='open "$(PWD)"'

## GIT
alias glol='git log --pretty=format:"%h %an %ad %s" --name-only --graph'
alias glog='git log --graph'

#_______________________________________________ Function __________________________________________
## Backup
function backup_bzv() {
cp -R ~/.bash_profile ~/Documents/For\ Sys/Backup/
cp -R ~/.zshrc ~/Documents/For\ Sys/Backup/
cp -R ~/.vimrc ~/Documents/For\ Sys/Backup/
}

function upload_bzv() {
cp -R ~/Documents/For\ Sys/Backup/.bash_profile ~/
cp -R ~/Documents/For\ Sys/Backup/.zshrc ~/
cp -R ~/Documents/For\ Sys/Backup/.vimrc ~/
}
