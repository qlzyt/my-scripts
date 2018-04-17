#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Created by kevinkai on 2018/4/16



#生成器计算下一个元素的值使用next(),一般用for循环来迭代
#将一个函数的返回值变成一个生成器generator使用yield

def fib(max):
    n, a, b = 0, 0, 1
    while n < max:
        print(b)
        a, b = b, a + b
        n = n + 1
    return 'done'

def fib2(max):
    n, a, b = 0, 0, 1
    while n < max:
        yield b
        a, b = b, a + b
        n = n + 1
    return "done"

def triangles(n):
    list = [1]
    while n>0:
        yield list
        list= [1] + [x+y for x,y in zip(list[:],list[1:])] + [1]
        n-=1
    return


def mygenerator(*args):
    L=[]
    for i in args:
        L.append(i)
    yield L
    return


if __name__ == '__main__':
    # print(fib(5))
    #
    # g=fib2(2)
    # try:
    #     print(next(g))
    #     print(next(g))
    #     print(next(g))
    # except StopIteration as e:
    #     print(e.value)
    #
    # g=triangles(7)
    # for i in g:
    #     print(i)

    a=4
    g=mygenerator(a)
    # print(g)
    print(next(g))
    # for i in g:
    #     print(i)
