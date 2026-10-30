// Approve the change requests of the Kargo workshop and move them to Implement.
//
// For Lab 12. Run it in ServiceNow as an administrator, when the attendees have promoted prod:
// save it as a Fix Script (All > System Definition > Fix Scripts) and press Run Fix Script, or paste it in Scripts - Background.
// It only touches change requests that:
//   - were created by the integration user (CREATED_BY), and
//   - have a short description that starts with PREFIX, and
//   - are waiting: Authorize (-3) or Scheduled (-2).
// Run it again if some of them are still in Scheduled: the approvals can take a few seconds to move a change on.
//
// Set DRY_RUN to true to only list what it would do.

(function () {
  var DRY_RUN = false;
  var PREFIX = 'Kargo workshop';
  var CREATED_BY = 'kargo-workshop';

  var AUTHORIZE = '-3';
  var SCHEDULED = '-2';
  var IMPLEMENT = '-1';

  var counts = { approved: 0, implemented: 0, waiting: 0, failed: 0 };

  var cr = new GlideRecord('change_request');
  cr.addQuery('short_description', 'STARTSWITH', PREFIX);
  cr.addQuery('sys_created_by', CREATED_BY);
  cr.addQuery('state', 'IN', AUTHORIZE + ',' + SCHEDULED);
  cr.orderBy('sys_created_on');
  cr.query();

  while (cr.next()) {
    var sysId = cr.getUniqueValue();
    var number = cr.getValue('number');

    // 1. Authorize: approve every approval that is still requested
    if (cr.getValue('state') === AUTHORIZE) {
      var approval = new GlideRecord('sysapproval_approver');
      approval.addQuery('sysapproval', sysId);
      approval.addQuery('state', 'requested');
      approval.query();
      var n = 0;
      while (approval.next()) {
        n++;
        if (!DRY_RUN) {
          approval.setValue('state', 'approved');
          approval.update();
        }
      }
      counts.approved += n > 0 ? 1 : 0;
      gs.print(number + ': ' + n + ' approvals ' + (DRY_RUN ? 'would be approved' : 'approved'));
    }

    // 2. Scheduled: move it to Implement (read it again, the approvals may have moved it on)
    var fresh = new GlideRecord('change_request');
    fresh.get(sysId);
    if (DRY_RUN) {
      gs.print(number + ': would move to Implement once it is in Scheduled');
      continue;
    }
    if (fresh.getValue('state') === SCHEDULED) {
      fresh.setValue('state', IMPLEMENT);
      fresh.update();
      var now = new GlideRecord('change_request');
      now.get(sysId);
      if (now.getValue('state') === IMPLEMENT) {
        counts.implemented++;
        gs.print(number + ': now in Implement');
      } else {
        counts.failed++;
        gs.print(number + ': could not move to Implement, it is in state ' + now.getValue('state'));
      }
    } else if (fresh.getValue('state') === IMPLEMENT) {
      // The approvals were enough: the change moved on to Implement by itself
      counts.implemented++;
      gs.print(number + ': now in Implement');
    } else {
      counts.waiting++;
      gs.print(number + ': in state ' + fresh.getValue('state') + ', run the script again in a few seconds');
    }
  }

  gs.print('Done. Approved: ' + counts.approved + ', in Implement: ' + counts.implemented +
    ', waiting: ' + counts.waiting + ', failed: ' + counts.failed + (DRY_RUN ? ' (dry run)' : ''));
})();
