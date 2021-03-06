#!/usr/bin/python

import sys
import os
import platform
import httplib
import urllib
import base64
import json

DOCUMENTATION = '''
---
module: aemgroup
short_description: Manage AEM groups
description:
    - Create, modify and delete AEM groups
author: Paul Markham
notes:  
        - This module only does basic group management. It doesn't handle access control lists so it's not that useful.
          It's more to create groups that contain other groups, e.g. a 'sysadmin' group is in the administrator group;
          'developers' are in the 'readonly' group.
options:
    id:
        description:
            - The AEM group ID
        required: true
    state:
        description:
            - Create or delete the group
        required: true
        choices: [present, absent]
    name:
        description:
            - Descriptive name of group.
              Only required when creating a new account.
        required: true
    groups:
        description:
            - The of groups the account is in.
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
# Create a group
- aemgroup: id=sysadmin
           name='Systems Administrators'
           groups='administrators'
           host=auth01
           port=4502
           admin_user=admin
           admin_password=admin
           state=present

# Delete a group
- aemgroup: id=devs
           host=auth01
           port=4502
           admin_user=admin
           admin_password=admin
           state=absent
'''

# --------------------------------------------------------------------------------
# AEMGroup class.
# --------------------------------------------------------------------------------
class AEMGroup(object):
    def __init__(self, module):
        self.module         = module
        self.state          = self.module.params['state']
        self.id             = self.module.params['id']
        self.name           = self.module.params['name']
        self.groups         = self.module.params['groups']
        self.admin_user     = self.module.params['admin_user']
        self.admin_password = self.module.params['admin_password']
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
          
        self.get_group_info()



    # --------------------------------------------------------------------------------
    # Look up package info.
    # --------------------------------------------------------------------------------
    def get_group_info(self):
        if self.aem61:
            (status, output) = self.http_request('GET', '/bin/querybuilder.json?path=/home/groups&1_property=rep:authorizableId&1_property.value=%s&p.limit=-1&p.hits=full' % self.id)
            if status != 200:
                self.module.fail_json(msg='Error searching for group. status=%s output=%s' % (status, output))
            info = json.loads(output)
            if len(info['hits']) == 0:
                self.exists = False
                return
            self.path = info['hits'][0]['jcr:path']
        else:
            self.path = '/home/groups/%s/%s' % (self.id_initial, self.id)

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


    # --------------------------------------------------------------------------------
    # state='present'
    # --------------------------------------------------------------------------------
    def present(self):
        if self.exists:
            # Update existing group
            if self.name:
                if self.curr_name != self.name:
                    self.update_name()

            if self.groups:
                self.curr_groups.sort()
                self.groups.sort()
                curr_groups = ','.join(self.curr_groups).lower()
                groups = ','.join(self.groups).lower()
                if curr_groups != groups:
                    self.update_groups()
        else:
            # Create new group
            if not self.name:
                self.module.fail_json(msg='Missing required argument: name')
            self.create_group()

    # --------------------------------------------------------------------------------
    # state='absent'
    # --------------------------------------------------------------------------------
    def absent(self):
        if self.exists:
            self.delete_group()

    # --------------------------------------------------------------------------------
    # Create a new group
    # --------------------------------------------------------------------------------
    def create_group(self):
        fields = [
            ('createGroup', ''),
            ('authorizableId', self.id),
            ('profile/givenName', self.name),
            ]
        if not self.module.check_mode:
            if self.groups:
                for group in self.groups:
                    fields.append(('membership', group))
            (status, output) = self.http_request('POST', '/libs/granite/security/post/authorizables', fields)
            self.get_group_info()
            if status != 201 or not self.exists:
                self.module.fail_json(msg='failed to create group: %s - %s' % (status, output))
        self.changed = True
        self.msg.append("group '%s' created" % (self.id))
    
    # --------------------------------------------------------------------------------
    # Update name
    # --------------------------------------------------------------------------------
    def update_name(self):
        fields = [('profile/givenName', self.name)]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to update name: %s - %s' % (status, output))
        self.changed = True
        self.msg.append("name changed from '%s' to '%s'" % (self.curr_name, self.name))

    # --------------------------------------------------------------------------------
    # Update groups
    # --------------------------------------------------------------------------------
    def update_groups(self):
        fields = []
        if not self.module.check_mode:
            for group in self.groups:
                fields.append(('membership', group))
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to update groups: %s - %s' % (status, output))
        self.changed = True
        self.msg.append("groups updated from '%s' to '%s'" % (self.curr_groups, self.groups))

    # --------------------------------------------------------------------------------
    # Delete a group
    # --------------------------------------------------------------------------------
    def delete_group(self):
        fields = [('deleteAuthorizable', '')]
        if not self.module.check_mode:
            (status, output) = self.http_request('POST', '%s.rw.html' % (self.path), fields)
            if status != 200:
                self.module.fail_json(msg='failed to delete group: %s - %s' % (status, output))
        self.changed = True
        self.msg.append("group '%s' deleted" % (self.id))

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
            name           = dict(default=None),
            groups         = dict(default=None, type='list'),
            admin_user     = dict(required=True),
            admin_password = dict(required=True, no_log=True),
            host           = dict(required=True),
            port           = dict(required=True, type='int'),
            version        = dict(required=True),
            ),
        supports_check_mode=True
        )

    group = AEMGroup(module)
    
    state = module.params['state']


    if state == 'present':
        group.present()
    elif state == 'absent':
        group.absent()
    else:
        module.fail_json(msg='Invalid state: %s' % state)

    group.exit_status()

# --------------------------------------------------------------------------------
# Ansible boiler plate code.
# --------------------------------------------------------------------------------
from ansible.module_utils.basic import *
main()
