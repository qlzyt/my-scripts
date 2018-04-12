#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Created by kevinkai on 2018/4/12

#一层循环
L=[n * n for n in range(1,10)]
print(L)

#二层循环
L2=[m + n for m in 'ABC' for n in 'XYZ']
print(L2)

if __name__ == '__main__':
    pass