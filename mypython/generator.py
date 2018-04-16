#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Created by kevinkai on 2018/4/16



#生成器计算下一个元素的值使用next(),一般用for循环来迭代


# g=(x*y for x in (1,10) for y in range(5))
# for i in g:
#     print(i)
# print(type(g))



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



if __name__ == '__main__':
    print(fib(5))

    g=fib2(2)
    try:
        print(next(g))
        print(next(g))
        print(next(g))
    except StopIteration as e:
        print(e.value)

    g=triangles(7)
    for i in g:
        print(i)