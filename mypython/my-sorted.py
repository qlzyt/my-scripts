#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Created by kevinkai on 2018/4/19

import collections
import operator

# L=[1,2,3,4,5,6,-10]
# print(sorted(L,key=abs))
#
#
# L1 = [('Bob', 75, 1), ('Adam', 92, 3), ('Bart', 66, 2), ('Lisa', 88, 4)]
# print(sorted(L1,key=lambda score:score[1]))
# print(sorted(L1,key = operator.itemgetter(1)))

int = "Hello World!"
print(type(int.lower()))

# L=list(int)
# print(L)
# def myfilter(list2):
#     return lambda kk: kk.isalpha()
#
# def mylowwer(mylist):
#     listk = [ i.lower() for i in mylist]
#     return listk
#
# list2=mylowwer(L)
# print(list2)
#
# list3 = filter(myfilter(list2),list2)
# print(list3)
# mysetL=set(list3)
# L2=[]
#
# for item in mysetL:
#     L2.append([item,list3.count(item)])
# a=sorted(L2,key=operator.itemgetter(1,0))
# # print(a[-1][1])
# if a[-1][1] > a[0][1]:
#     print(a[-1][0])
# else:
#     print(a[0][0])
# print(a)



# if __name__ == '__main__':
#     pass