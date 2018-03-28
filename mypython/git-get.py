#!/usr/bin/python2
# -*- coding: GBK -*-
# write by holyzhou

import sys
from os import path
import requests
from urlparse import urljoin
from urlparse import urlparse
from urlparse import urlunparse
from posixpath import normpath
from bs4 import BeautifulSoup
from re import  compile, IGNORECASE
from prettytable import PrettyTable
from pygit2 import clone_repository


class git_get(object):
    def __init__(self, login_name, login_passwd, http_hostname):
        self.name = login_name
        self.passwd = login_passwd
        self.http_hostname = http_hostname
        parse_object = urlparse(self.http_hostname)
        self.hostname = parse_object.netloc
        self.http_handler = self.login()
        self.project_url_dict = self.get_project()

    def url_join(self, baseurl, suffix):
        url = urljoin(baseurl.strip(), suffix.strip())
        arr = urlparse(url)
        return urlunparse((arr.scheme, arr.netloc, normpath(arr[2]), arr.params, arr.query, arr.fragment))

    def format_rn(self, strings):
        self.strings = strings
        content = self.strings.replace('\r\n', '\r').replace('\r', '\r\n').replace('\r\n', '\n').replace('\n', '\r\n')
        return content

    def login(self):
        suffix = "?wicket:interface=:0:userPanel:loginForm::IFormSubmitListener::"
        post_url = self.url_join(self.http_hostname, suffix)
        user_agent = "'User-Agent': 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:45.0) Gecko/20100101 Firefox/45.0'"
        headers = {
            "Host": self.hostname,
            "User-Agent": user_agent,
            "Referer": self.http_hostname
        }
        user_data = {
                "wicket:bookmarkablePage": ":com.gitblit.wicket.pages.MyDashboardPage",
                "id1_hf_0": "",
                "username": self.name,
                "password": self.passwd
                }
        s = requests.Session()
        r = s.post(post_url, data= user_data, headers= headers)
        if r.status_code == 200:
            return s

    def get_project(self):
        suffix = "/user/qa-release"
        user_center = self.url_join(self.http_hostname, suffix)
        s = self.http_handler.get(user_center)
        content = self.format_rn(s.text)
        git_pattern = ".*summary.*git$"
        soup = BeautifulSoup(content,  "html.parser")
        doc = soup.find_all("a", attrs={"href": compile(git_pattern, IGNORECASE)})
        self.project_url_dict = {}
        for line in doc:
            key = line.get_text()
            value = line.get("href")
            value = self.url_join(weburl, value)
            self.project_url_dict[key] = value
        return self.project_url_dict

    def showlist(self):
        x = PrettyTable()
        x.field_names = [ "project_name" ]
        [ x.add_row([k])  for  k, v in  self.project_url_dict.iteritems() ]
        x.align = "l"
        print x
        return self

    def ver_url(self, project_name):
        self.project_name = project_name
        self.ver_url_dict = {}
        git_url = self.project_url_dict[project_name]
        content = self.http_handler.get(git_url)
        content = self.format_rn(content.text)
        soup = BeautifulSoup(content, "html.parser")
        d_ver = soup.find_all("a", attrs={"class": "list name"})
        ver_list = [ line.get_text() for line in d_ver ]
        d_git = soup.find_all("span", attrs={"class": "commandMenuItem"})
        git_url = [line.get_text() for line in d_git if "ssh" not in line.get_text()]
        git_url = "".join(git_url)
        self.ver_url_dict[project_name] = [ver_list, git_url]
        return self.ver_url_dict

    def show_ver_url(self):
        x = PrettyTable()
        x.field_names = [ self.project_name ]
        ver_list = self.ver_url_dict[self.project_name][0]
        ver_list.sort(reverse = True)
        [ x.add_row([ver]) for ver in ver_list ]
        print(x)

    def git_clone_branch(self, project_name, branch, localpath="."):
        git_url = self.ver_url_dict[project_name][1]
        old_str = "%s@" % self.name
        new_str = "%s:%s@" % (self.name, self.passwd)
        git_url = git_url.replace(old_str, new_str)
        git_url = git_url.replace("git clone","").strip()
        repo_path = localpath
        clone_repository(git_url, repo_path, checkout_branch=branch)

if __name__ == "__main__":
    weburl = "http://gitblit.sumscope.com:81/"
    login_name = "qa-release"
    login_passwd = "123456"
    if len(sys.argv) == 2 and sys.argv[1] == "prolist":
        s = git_get(login_name, login_passwd, weburl)
        s.showlist()
    elif len(sys.argv) == 3 and sys.argv[1] == "brlist":
        s = git_get(login_name, login_passwd, weburl)
        s.ver_url(sys.argv[2])
        s.show_ver_url()
    elif len(sys.argv) == 4 and sys.argv[1] == "gitget":
        s = git_get(login_name, login_passwd, weburl)
        project_name = sys.argv[2]
        branch = sys.argv[3]
        s.ver_url(project_name)
        localpath = path.abspath(".")
        print "clone %s %s to %s" % (project_name, branch, localpath)
        try:
            s.git_clone_branch(project_name, branch, localpath)
        except ValueError, e:
            print e
    elif len(sys.argv) == 6 and sys.argv[1] == "gitget":
        s = git_get(login_name, login_passwd, weburl)
        project_name = sys.argv[2]
        branch = sys.argv[3]
        s.ver_url(project_name)
        if sys.argv[4] == "-d":
            localpath = path.abspath(sys.argv[5])
            print "clone %s %s to %s" % (project_name, branch, localpath)
            try:
                s.git_clone_branch(project_name, branch, localpath)
            except ValueError, e:
                print e

        else:
            info = """usage: %s
                            prolist (show all project list)
                            brlist {project name} (show specified project branch list)
                            gitget  {project name} {branch version} "[-d] {dirctory}"
                            <git clone special branch from remote. -d is optional>
                            help (show this info)""" % sys.argv[0]
            print info
    elif len(sys.argv) == 2 and sys.argv[1] == "help":
        info = """usage: %s
                        prolist (show all project list)
                        brlist {project name} (show specified project branch list)
                        gitget  {project name} {branch version} "[-d] {dirctory}"
                        <git clone special branch from remote. -d is optional>
                        help (show this info)""" % sys.argv[0]
        print info
    else:
        info = """usage: %s
                        prolist (show all project list)
                        brlist {project name} (show specified project branch list)
                        gitget  {project name} {branch version} "[-d] {dirctory}"
                        <git clone special branch from remote. -d is optional>
                        help (show this info)""" % sys.argv[0]
        print info