#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Author: kevinkai
# Created by iFantastic on 2018/4/11


#函数在内部调用了函数本身，这个函数就是递归函数
def fact(n):
    if n==1:
        return 1
    return n * fact(n - 1)

def myRecusive(name):
    if name == "zk":
        print("this is error name")
        exit(0)
    else:
        print(name)
        exit(0)
    return myRecusive(name)








if __name__ == '__main__':
    myRecusive("zk")