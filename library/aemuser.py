#!/usr/bin/python

import sys
import os
import platform
import httplib
import urllib
import base64
import json
import string
import random
import re


DOCUMENTATION = '''
---
module: aemuser
short_description: Manage AEM users
description:
    - Create, modify and delete AEM users
author: Paul Markham
notes:
    - The password specified is the initial password and is only used when the account is created.
      If the account exists, the password isn't changed.
options:
    id:
        description:
            - The AEM user name
        required: true
    state:
        description:
            - Create or delete the account
        required: true
        choices: [present, absent]
    first_name:
        description:
            - First name of user.
              Only required when creating a new account.
        required: true
    last_name:
        description:
            - Last name of user.
              Only required when creating a new account.
        required: true
    password:
        description:
            - Initial password when account is created. Not used if account already exists.
              Only required when creating a new account.
        required: true
    groups:
        description:
            - The id of groups the account is in.
              Only required when creating a new account.
        required: true
        default: null
    admin_user:
        description:
            - AEM admin user account name
        required: true
    admin_password:
        description:
            - AEM admin user account password
        required: true
    host:
        description:
            - Host name where AEM is running
        required: true
    port:
        description:
            - Port number that AEM is listening on
        required: true
'''

EXAMPLES='''
# Create a user
- aemuser: id=bbaggins
          first_name=Bilbo
          last_name=Baggins
          password=myprecious
          groups='immortality,invisibility'
          host=auth01
          port=4502
          admin_user=admin
          admin_password=admin
          state=present

# Delete a user
- aemuser: id=gollum
          host=auth01
          port=4502
          admin_user=admin
          admin_password=admin
          state=absent
'''
# --------------------------------------------------------------------------------
# AEMUser class.
# --------------------------------------------------------------------------------
class AEMUser(object):
    def __init__(self, module):
        self.module         = module
        self.state          = self.module.params['state']
        self.id             = self.module.params['id']
        self.first_name     = self.module.params['first_name']
        self.last_name      = self.module.params['last_name']
        self.mail           = self.module.params['mail']
        self.groups         = self.module.params['groups']
        self.password       = self.module.params['password']
        self.admin_user     = self.module.params['admin_user']
        self.admin_password = self.module.params['admin_password']
        self.replicate      = self.module.params['replicate']
        self.host           = self.module.params['host']
        self.port           = self.module.params['port']
        self.version        = self.module.params['version']
        
        self.changed = False
        self.msg = []
        self.id_initial = self.id[0]

        if self.module.check_mode:
            self.msg.append('Running in check mode')

        self.aem61 = False
        ver = self.version.split('.')
        if int(ver[0]) >= 6:
            if self.state != 'absent':
            # aem6 must have all groups and all users in the 'everyone' group 
            	if not "everyone" in self.groups:
                	 # everyone group not listed, so add it
                 	self.groups.append("everyone")
            if int(ver[1]) >=1:
                self.aem61 = True

        self.get_user_info()


    # --------------------------------------------------------------------------------
    # Look up user info.
    # --------------------------------------------------------------------------------
    def get_user_info(self):
        if self.aem61:
            (status, output) = self.http_request('GET', '/bin/querybuilder.json?path=/home/users&1_property=rep:authorizableId&1_property.value=%s&p.limit=-1&p.hits=full' % self.id)
            if status != 200:
                self.module.fail_json(msg="Error searching for user '%s'. status=%s output=%s" % (self.id, status, output))
            info = json.loads(output)
            if len(info['hits']) == 0:
                self.exists = False
                return
            self.path = info['hits'][0]['jcr:path']
        else:
            self.path = '/home/users/%s/%s' % (self.id_initial, self.id)

        (status, output) = self.http_request('GET', '%s.rw.json?props=*' % (self.path))
        if status == 200:
            self.exists = True
            info = json.loads(output)
            self.curr_name = info['name']
            self.curr_groups = []
            for entry in info['declaredMemberOf']:
                self.curr_groups.append(entry['authorizableId'])

        else:
            self.exists = False

        (status, output) = self.http_request('GET', '%s.preferences.json' % (self.path))
        if status == 200:
            self.exists = True
            info = json.loads(output)
            if info['user']['email']: 
	        self.curr_mail = info['user']['email']
        else:
            self.exists = False

    # --------------------------------------------------------------------------------
    # state='present'
    # --------------------------------------------------------------------------------
    def present(self):
        if self.exists:
            # Update existing user
            if self.first_name and self.last_name:
                full_name = '%s %s' % (self.first_name, self.last_name)
                if self.curr_name != full_name:
                    self.update_name()
            elif self.first_name and not self.last_name:
                self.module.fail_json(msg='Missing required argument: last_name')
            elif self.last_name and not self.first_name:
                self.module.fail_json(msg='Missing required argument: first_name')
               
            if self.groups:
                self.curr_groups.sort()
                self.groups.sort()
                curr_groups = ','.join(self.curr_groups)
                groups = ','.join(self.groups)
                if curr_groups != groups:
                    self.update_groups()

	    if self.mail:
                if self.curr_mail != self.mail:
	   	   self.update_mail()

        else:
            # Create a new user
            if self.password:
                self.check_password()
            else:
                self.generate_password()
            if not self.first_name:
                self.module.fail_json(msg='Missing required argument: first_name')
            if not self.last_name:
                self.module.fail_json(msg='Missing required argument: last_name')
            if not self.groups:
                self.module.fail_json(msg='Missing required argument: groups')
            self.create_user()

    # --------------------------------------------------------------------------------
    # state='absent'
    # --------------------------------------------------------------------------------
    def absent(self):
        if self.exists:
            self.delete_user()

    # --------------------------------------------------------------------------------
    # Create a new user
    # --------------------------------------------------------------------------------
    def create_user(self):
        fields = [
            ('createUser', ''),
            ('authorizableId', self.id),
            ('profile/givenName', self.first_name),
            ('profile/familyName', self.last_name),
            ('profile/email', self.mail),
            ('intermediatePath', '/home/users/altria'),
            ]
   # Added path so that users for altria will be added the specific path

        if not self.module.check_mode:
            if self.password:
                fields.append(('rep:password', self.password))
            for group in self.groups:
                fields.append(('membership', group))
            (status, output) = self.http_request('POST', '/libs/granite/security/post/authorizables', fields)
            self.get_user_info()
            if status != 201 or not self.exists:
                self.module.fail_json(msg='failed to create user: %s - %s' % (status, output))
        self.msg.append("user '%s' created" % (self.id))
        if self.replicate:
            self.replicate_user()
        self.changed = True
    
    # --------------------------------------------------------------------------------
    # Update name
    # --------------------------------------------------------------------------------
    def update_name(self):
        fields = [
            ('profile/givenName', self.first_name),
            ('profile/familyName', self.last_name),
            ('profile/email', self.mail),
            ]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to update name or email : %s - %s' % (status, output))
        if self.replicate:
            self.replicate_user()
        self.changed = True
        self.msg.append("name updated from '%s' to '%s %s'" % (self.curr_name, self.first_name, self.last_name))

    def update_mail(self):
        fields = [
            ('profile/email', self.mail),
            ]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to update mail: %s - %s' % (status, output))
        if self.replicate:
            self.replicate_user()
        self.changed = True
        self.msg.append("mail updated from '%s' to '%s'" % (self.curr_mail, self.mail))

    # --------------------------------------------------------------------------------
    # Update groups
    # --------------------------------------------------------------------------------
    def update_groups(self):
        fields = []
        for group in self.groups:
            fields.append(('membership', group))
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to update groups: %s - %s' % (status, output))
        if self.replicate:
            self.replicate_user()
        self.changed = True
        self.msg.append("groups updated from '%s' to '%s'" % (self.curr_groups, self.groups))

    # --------------------------------------------------------------------------------
    # Delete a user
    # --------------------------------------------------------------------------------
    def delete_user(self):
        fields = [('deleteAuthorizable', '')]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to delete user: %s - %s' % (status, output))
        self.deactivate_user()
        self.changed = True
        self.msg.append("user '%s' deleted" % (self.id))
    #---------------------------------------------------------------------------------
    # Replicate user
    #---------------------------------------------------------------------------------
    def replicate_user(self):
        fields = [
            ('path', self.path),
            ('cmd','activate')]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '/bin/replicate.json', fields)
            if status != 200:
                self.module.fail_json(msg='failed to replicate user %s - %s' % (status, output))
        self.msg.append("user '%s' replicated" % (self.id))

    #---------------------------------------------------------------------------------
    # Deactivate user
    #---------------------------------------------------------------------------------
    def deactivate_user(self):
        fields = [
            ('path', self.path),
            ('cmd','DeActivate')]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '/bin/replicate.json', fields)
            if status != 200:
                self.module.fail_json(msg='failed to deactivate user %s - %s' % (status, output))
        self.msg.append("user '%s' deactivated" % (self.id))
    # --------------------------------------------------------------------------------
    # Issue http request.
    # --------------------------------------------------------------------------------
    def http_request(self, method, url, fields = None):
        headers = {'Authorization' : 'Basic ' + base64.b64encode(self.admin_user + ':' + self.admin_password)}
        if fields:
            data = urllib.urlencode(fields)
            headers['Content-type'] = 'application/x-www-form-urlencoded'
        else:
            data = None
        conn = httplib.HTTPConnection(self.host + ':' + str(self.port))
        try:
            conn.request(method, url, data, headers)
        except Exception as e:
            self.module.fail_json(msg="http request '%s %s' failed: %s" % (method, url, e))
        resp = conn.getresponse()
        output = resp.read()
        return (resp.status, output)

    # --------------------------------------------------------------------------------
    # Generate a random password 
    # --------------------------------------------------------------------------------
    def generate_password(self):
        chars = string.ascii_letters + string.digits + '!@#$%^&*()-_=+.,:;|?'
        self.password = ''
        for i in range(0,16):
            self.password += random.choice(chars)
        self.msg.append("generated password '%s'" % self.password)


    # --------------------------------------------------------------------------------
    # Check strength of a password
    # Adapted from: http://thelivingpearl.com/2013/01/02/generating-and-checking-passwords-in-python/
    # --------------------------------------------------------------------------------
    def check_password(self):
        #strength = ['Blank','Very Weak','Weak','Medium','Strong','Very Strong']
        score = 1

        if len(self.password) < 1:
            return strength[0]
        if len(self.password) < 4:
            return strength[1]
    
        if len(self.password) >=8:
            score = score + 1
        if len(self.password) >=12:
            score = score + 1
        
        if re.search('\d+',self.password):
            score = score + 1
        if re.search('[a-z]',self.password) and re.search('[A-Z]',self.password):
            score = score + 1
        if re.search('.,[,!,@,#,$,%,^,&,*,(,),_,~,-,]',self.password):
            score = score + 1
    
        if score < 4:
            self.module.fail_json(msg="Password too weak. Minimum length is 8, with characters from three of groups: upper, lower, numeric and special")
    

    # --------------------------------------------------------------------------------
    # Return status and msg to Ansible.
    # --------------------------------------------------------------------------------
    def exit_status(self):
        msg = ','.join(self.msg)
        self.module.exit_json(changed=self.changed, msg=msg)


# --------------------------------------------------------------------------------
# Mainline.
# --------------------------------------------------------------------------------
def main():
    module = AnsibleModule(
        argument_spec      = dict(
            id             = dict(required=True),
            state          = dict(required=True, choices=['present', 'absent']),
            first_name     = dict(default=None),
            last_name      = dict(default=None),
            mail           = dict(default=None),
            password       = dict(default=None, no_log=True),
            groups         = dict(default=None, type='list'),
            admin_user     = dict(required=True),
            admin_password = dict(required=True, no_log=True),
            replicate      = dict(required=False,default=False, type='bool'),
            host           = dict(required=True),
            port           = dict(required=True, type='int'),
            version        = dict(required=True),
            ),
        supports_check_mode=True
        )

    user = AEMUser(module)
    
    state = module.params['state']

    if state == 'present':
        user.present()
    elif state == 'absent':
        user.absent()
    else:
        module.fail_json(msg='Invalid state: %s' % state)

    user.exit_status()

# --------------------------------------------------------------------------------
# Ansible boiler plate code.
# --------------------------------------------------------------------------------
from ansible.module_utils.basic import *
main()
